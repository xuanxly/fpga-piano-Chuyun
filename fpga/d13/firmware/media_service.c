#include "media_hw.h"
#include "ff.h"
#include "diskio.h"
#include "game_chart.h"
#include <stdint.h>
#include <string.h>

// 内部琴音在主音量之前录制。录放互斥，5分钟限制按实际写入样本计算，暂停不占时长。
#define RATE 48000u
#define MAX_SAMPLES (RATE*300u)
#define ROWS 6
static FATFS fs;
static FIL stream;
static TCHAR cwd[256],names[ROWS][256],selected[256];
static uint8_t entry_attr[ROWS];
static uint32_t ui[68],recorded,rec_total,rec_number,list_offset,total_entries,capacity_mb;
static unsigned mounted,rec_state,play_state,message,entry_count,stream_open,kind;
static uint32_t next_mount,next_publish,play_base,play_seconds,play_duration,data_begin,data_bytes,source_rate,source_channels;
static uint32_t stream_data_read,resample_phase,last_sync;
static int16_t pcm[1024],previous_l,previous_r;
static unsigned pcm_frames,pcm_at,pcm_channels,resample_started,eof_draining;
static unsigned char io_buffer[2048];

static unsigned low(unsigned x){return x>='A'&&x<='Z'?x+32:x;}
static void widen(TCHAR*d,const char*s){while((*d++=(uint8_t)*s++)){};}
static unsigned tlen(const TCHAR*s){unsigned n=0;while(s[n])n++;return n;}
static void tcopy(TCHAR*d,const TCHAR*s){while((*d++=*s++)){};}
static uint16_t le16(const unsigned char*p){return p[0]|(uint16_t)p[1]<<8;}
static uint32_t le32(const unsigned char*p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put16(unsigned char*p,unsigned n){p[0]=n;p[1]=n>>8;}
static void put32(unsigned char*p,uint32_t n){p[0]=n;p[1]=n>>8;p[2]=n>>16;p[3]=n>>24;}
static void text_row(unsigned row,const TCHAR*s){
    unsigned char*d=(unsigned char*)ui+row*32;for(unsigned i=0;i<32;i++)d[i]=' ';
    for(unsigned i=0;s[i]&&i<31;i++)d[i]=(s[i]>=32&&s[i]<127)?s[i]:'?';
}
static unsigned game_stream,game_practice,usb_exported;
static const TCHAR songs_dir[];
static int suffix(const TCHAR*s,const char*ext){unsigned n=tlen(s);return n>=4&&s[n-4]=='.'&&low(s[n-3])==(unsigned)ext[0]&&low(s[n-2])==(unsigned)ext[1]&&low(s[n-1])==(unsigned)ext[2];}
static void publish(void){
    uint32_t now=hw_read(HW_MS);
    unsigned progress=play_duration?(uint32_t)((uint64_t)play_seconds*100/play_duration):0;if(progress>100)progress=100;
    ui[64]=(mounted?1u:0)|(fs.fs_type==FS_EXFAT?2u:0)|(rec_state<<2)|(play_state<<5)|(progress<<8)|(message<<16);
    ui[65]=recorded/RATE | (play_seconds<<16);
    ui[66]=play_duration | (entry_count<<16);
    ui[67]=capacity_mb;
    for(unsigned i=0;i<68;i++)hw_write(HW_UI_BASE+i*4,ui[i]);hw_write(HW_UI_COMMIT,1);next_publish=now+100;
}
static void error(unsigned msg){message=msg;publish();}
static int join_path(TCHAR*out,const TCHAR*name){
    unsigned a=tlen(cwd),b=tlen(name);if(a+b+2>256)return 0;
    tcopy(out,cwd);if(a&&out[a-1]!='/')out[a++]='/';tcopy(out+a,name);return 1;
}
static void list_directory(void){
    DIR dir;FILINFO info;entry_count=0;total_entries=0;
    for(unsigned i=0;i<ROWS;i++){names[i][0]=0;entry_attr[i]=0;text_row(i,names[i]);}
    if(!mounted)return;
    if(f_opendir(&dir,hw_read(HW_PAGE)==PAGE_GAME?songs_dir:cwd)!=FR_OK){error(MSG_IO_ERROR);return;}
    for(;;){FRESULT r=f_readdir(&dir,&info);if(r!=FR_OK){message=MSG_IO_ERROR;break;}if(!info.fname[0])break;
        if(info.fname[0]=='.'&&(info.fname[1]==0||(info.fname[1]=='.'&&info.fname[2]==0)))continue;
        if(hw_read(HW_PAGE)==PAGE_GAME&&((info.fattrib&AM_DIR)||!suffix(info.fname,"csv")))continue;
        if(total_entries>=list_offset&&entry_count<ROWS){
            tcopy(names[entry_count],info.fname);entry_attr[entry_count]=info.fattrib;text_row(entry_count,info.fname);
            if(info.fattrib&AM_DIR)((unsigned char*)ui)[entry_count*32+31]='/';entry_count++;
        }total_entries++;
    }f_closedir(&dir);
    text_row(6,hw_read(HW_PAGE)==PAGE_GAME?songs_dir:cwd);if(!total_entries)message=MSG_EMPTY;publish();
}
static void mount_card(void){
    static const TCHAR empty[]={0};
    if(rec_state==REC_RUNNING||rec_state==REC_PAUSED||stream_open)return;
    mounted=0;
    if(disk_initialize(0)){message=MSG_NO_CARD;next_mount=hw_read(HW_MS)+2000;publish();return;}
    if(f_mount(&fs,empty,1)!=FR_OK){message=MSG_MOUNT_ERROR;next_mount=hw_read(HW_MS)+2000;publish();return;}
    LBA_t n=0;disk_ioctl(0,GET_SECTOR_COUNT,&n);capacity_mb=(uint32_t)(n/2048);
    mounted=1;list_offset=0;cwd[0]='/';cwd[1]=0;message=MSG_READY;list_directory();
}
static int write_bytes(const void*p,UINT n){UINT done=0;return f_write(&stream,p,n,&done)==FR_OK&&done==n;}
static int wave_header(uint32_t samples){
    unsigned char h[44];memset(h,0,sizeof(h));memcpy(h,"RIFF",4);put32(h+4,36+samples*2);memcpy(h+8,"WAVEfmt ",8);
    put32(h+16,16);put16(h+20,1);put16(h+22,1);put32(h+24,RATE);put32(h+28,RATE*2);put16(h+32,2);put16(h+34,16);
    memcpy(h+36,"data",4);put32(h+40,samples*2);return f_lseek(&stream,0)==FR_OK&&write_bytes(h,44);
}
static int drain_record(void){
    unsigned words=hw_read(HW_REC_COUNT)&0x7fff;unsigned n=words>512?512:words;
    unsigned bytes=0;
    for(unsigned i=0;i<n;i++){
        uint32_t w=hw_read(HW_REC_POP);unsigned valid=hw_read(HW_REC_LAST_VALID);
        if(!valid)break;
        put16(io_buffer+bytes,w);bytes+=2;recorded++;
        if(valid==2){put16(io_buffer+bytes,w>>16);bytes+=2;recorded++;}
    }
    if(bytes&&!write_bytes(io_buffer,bytes))return 0;
    return 1;
}
static void finish_record(unsigned msg){
    if(!stream_open||!(rec_state==REC_RUNNING||rec_state==REC_PAUSED))return;
    hw_write(HW_REC_CTL,0);rec_state=REC_SAVING;publish();
    int ok=1;while((hw_read(HW_REC_COUNT)&0x7fff)&&ok)ok=drain_record();
    if(ok)ok=wave_header(recorded)&&f_lseek(&stream,44u+recorded*2)==FR_OK&&f_truncate(&stream)==FR_OK;
    if(f_close(&stream)!=FR_OK)ok=0;stream_open=0;rec_state=ok?REC_IDLE:REC_ERROR;
    if(!ok)mounted=0;message=ok?msg:MSG_IO_ERROR;publish();
}
static void start_record(void){
    if(!mounted){error(MSG_NO_CARD);return;}
    if(game_stream||(hw_read(HW_GAME_CTL)&1)){error(MSG_UNSUPPORTED);return;}
    if(play_state==PLAY_RUNNING||play_state==PLAY_PAUSED){error(MSG_UNSUPPORTED);return;}
    rec_state=REC_PREPARING;message=MSG_LOADING;publish();
    TCHAR path[32];char ascii[24]="/REC0001.WAV";
    FRESULT result=FR_EXIST;
    for(unsigned attempt=0;attempt<9999&&result==FR_EXIST;attempt++){
        rec_number=rec_number%9999+1;unsigned n=rec_number;
        for(int i=7;i>=4;i--){ascii[i]=(char)('0'+n%10);n/=10;}widen(path,ascii);
        result=f_open(&stream,path,FA_CREATE_NEW|FA_WRITE);
    }
    if(result!=FR_OK){rec_state=REC_IDLE;error(MSG_IO_ERROR);return;}
    stream_open=1;recorded=0;text_row(7,path);
    // 尝试连续预分配减少实时写卡抖动。失败仍可正常逐簇写入；不覆盖已有文件。
    (void)f_expand(&stream,44u+MAX_SAMPLES*2u,1);
    if(!wave_header(0)){f_close(&stream);stream_open=0;rec_state=REC_ERROR;error(MSG_IO_ERROR);return;}
    game_practice=1;hw_write(HW_GAME_CTL,12);
    hw_write(HW_REC_CTL,4);hw_write(HW_REC_CTL,1);rec_state=REC_RUNNING;message=MSG_READY;last_sync=hw_read(HW_MS);publish();
}
static void stop_play(void){
    hw_write(HW_PLAY_CTL,0);hw_write(HW_PLAY_CTL,4);
    if(stream_open&&(play_state==PLAY_RUNNING||play_state==PLAY_PAUSED||play_state==PLAY_LOADING)){f_close(&stream);stream_open=0;}
    play_state=PLAY_IDLE;eof_draining=0;pcm_at=pcm_frames=0;publish();
}
static int read_exact(void*p,unsigned n){UINT got=0;return f_read(&stream,p,n,&got)==FR_OK&&got==n;}
static int wave_open(void){
    unsigned char h[16];if(!read_exact(h,12)||memcmp(h,"RIFF",4)||memcmp(h+8,"WAVE",4))return 0;
    unsigned format_seen=0;
    while(f_tell(&stream)+8<=f_size(&stream)){
        if(!read_exact(h,8))return 0;uint32_t size=le32(h+4),at=(uint32_t)f_tell(&stream);
        if(size>f_size(&stream)-at)return 0;
        if(!memcmp(h,"fmt ",4)){
            if(size<16||!read_exact(h,16)||le16(h)!=1||le16(h+14)!=16)return 0;
            source_channels=le16(h+2);source_rate=le32(h+4);format_seen=1;
        }else if(!memcmp(h,"data",4)&&format_seen){data_begin=at;data_bytes=size;break;}
        if(f_lseek(&stream,at+size+(size&1))!=FR_OK)return 0;
    }
    if(!format_seen||!data_bytes||source_channels<1||source_channels>2||source_rate<8000||source_rate>48000)return 0;
    play_duration=(data_bytes/(source_channels*2))/source_rate;stream_data_read=0;return 1;
}
static void open_entry(unsigned row){
    if(row>=entry_count||!mounted)return;
    if(entry_attr[row]&AM_DIR){TCHAR path[256];if(!join_path(path,names[row])){error(MSG_UNSUPPORTED);return;}tcopy(cwd,path);list_offset=0;list_directory();return;}
    if(rec_state==REC_RUNNING||rec_state==REC_PAUSED){error(MSG_END_REC_FIRST);return;}
    if(!suffix(names[row],"wav")){error(MSG_UNSUPPORTED);return;}
    stop_play();if(!join_path(selected,names[row])){error(MSG_UNSUPPORTED);return;}
    text_row(7,names[row]);play_state=PLAY_LOADING;message=MSG_LOADING;publish();
    if(f_open(&stream,selected,FA_READ)!=FR_OK){play_state=PLAY_ERROR;error(MSG_IO_ERROR);return;}
    if(f_size(&stream)>0xffffffffu){f_close(&stream);play_state=PLAY_ERROR;error(MSG_UNSUPPORTED);return;}
    stream_open=1;data_bytes=0;play_seconds=play_base=0;kind=1;
    int ok=wave_open();
    if(!ok){f_close(&stream);stream_open=0;play_state=PLAY_ERROR;error(MSG_UNSUPPORTED);return;}
    if(hw_read(HW_PAGE)!=PAGE_FILES){f_close(&stream);stream_open=0;play_state=PLAY_IDLE;return;}
    pcm_frames=pcm_at=0;resample_phase=0;resample_started=0;eof_draining=0;
    hw_write(HW_PLAY_CTL,4);play_state=PLAY_LOADING;message=MSG_READY;
    hw_write(HW_NAV,PAGE_PLAYER);publish();
}
static int decode_next(void){
    pcm_at=0;pcm_frames=0;
    if(kind==1){
        unsigned want=sizeof(io_buffer),left=data_bytes-stream_data_read;if(want>left)want=left;
        want-=want%(source_channels*2);if(!want)return 0;UINT got;
        if(f_read(&stream,io_buffer,want,&got)!=FR_OK||got!=want)return -1;
        stream_data_read+=got;pcm_channels=source_channels;pcm_frames=got/(source_channels*2);
        for(unsigned i=0;i<got/2;i++)pcm[i]=(int16_t)le16(io_buffer+i*2);return 1;
    }
    return -1;
}
static __attribute__((optimize("O2"))) void fill_playback(void){
    unsigned free_words=hw_read(HW_PLAY_FREE);
    while(free_words>8){
        if(pcm_at>=pcm_frames){if(hw_read(HW_EVENTS))break;int r=decode_next();if(r<0){stop_play();play_state=PLAY_ERROR;error(MSG_DECODE_ERROR);return;}if(!r){eof_draining=1;break;}}
        int16_t l=pcm[pcm_at*pcm_channels],r=pcm_channels==2?pcm[pcm_at*2+1]:l;
        if(source_rate==48000){
            // 本机录音与48kHz WAV无需重采样，逐样本原样送出，同时为SD读写保留CPU余量。
            hw_write(HW_PLAY_PUSH,(uint16_t)l|((uint32_t)(uint16_t)r<<16));free_words--;pcm_at++;
            continue;
        }
        if(!resample_started){previous_l=l;previous_r=r;resample_started=1;}
        while(resample_phase<48000){
            uint32_t fraction=(resample_phase*65536u)/48000u;
            int32_t ol=previous_l+(int32_t)(((int64_t)(l-previous_l)*fraction)>>16);
            int32_t or=previous_r+(int32_t)(((int64_t)(r-previous_r)*fraction)>>16);
            hw_write(HW_PLAY_PUSH,(uint16_t)ol|((uint32_t)(uint16_t)or<<16));free_words--;resample_phase+=source_rate;
        }
        resample_phase-=48000;previous_l=l;previous_r=r;pcm_at++;
        // 触摸事件在每个解码块边界检查，不逐采样访问慢速总线；保留暂停/跳转响应。
    }
    if(play_state==PLAY_LOADING&&(hw_read(HW_PLAY_FREE)<MEDIA_FIFO_WORDS-2048||eof_draining)){
        play_state=PLAY_RUNNING;hw_write(HW_PLAY_CTL,1);publish();
    }
    if(eof_draining&&hw_read(HW_PLAY_FREE)==MEDIA_FIFO_WORDS){hw_write(HW_PLAY_CTL,0);f_close(&stream);stream_open=0;play_state=PLAY_ENDED;publish();}
}
static void seek_play(unsigned fraction){
    if(!stream_open||rec_state==REC_RUNNING||rec_state==REC_PAUSED||play_duration==0)return;
    if(fraction>1000)fraction=1000;
    unsigned paused=play_state==PLAY_PAUSED;uint32_t offset;
    if(kind==1){offset=(uint32_t)((uint64_t)(data_bytes/(source_channels*2))*fraction/1000)*(source_channels*2);stream_data_read=offset;}
    if(offset>data_bytes)offset=data_bytes;
    hw_write(HW_PLAY_CTL,4);
    if(f_lseek(&stream,data_begin+offset)!=FR_OK){stop_play();error(MSG_IO_ERROR);return;}
    pcm_at=pcm_frames=0;resample_started=resample_phase=0;eof_draining=0;
    play_base=(uint32_t)((uint64_t)play_duration*fraction/1000);play_seconds=play_base;play_state=PLAY_LOADING;
    fill_playback();if(paused&&play_state==PLAY_RUNNING){play_state=PLAY_PAUSED;hw_write(HW_PLAY_CTL,3);}publish();
}
#include "game_service.inc"

#include "usb_disk_service.inc"

static void event(uint32_t e){
    unsigned cmd=e>>24,arg=e&0xffffff;
    if(usb_exported&&cmd!=CMD_USB_DISK)return;
    if(cmd==CMD_USB_DISK){usb_disk_toggle();return;}
    if(cmd==CMD_RECORD){if(rec_state==REC_RUNNING||rec_state==REC_PAUSED)finish_record(MSG_SAVED);else start_record();}
    else if(cmd==CMD_REC_PAUSE){if(rec_state==REC_RUNNING){rec_state=REC_PAUSED;hw_write(HW_REC_CTL,3);}else if(rec_state==REC_PAUSED){rec_state=REC_RUNNING;hw_write(HW_REC_CTL,1);}publish();}
    else if(cmd==CMD_PAGE){if(arg==PAGE_VERIFY&&(rec_state==REC_RUNNING||rec_state==REC_PAUSED))finish_record(MSG_SAVED);if(arg!=PAGE_PLAYER&&(play_state==PLAY_RUNNING||play_state==PLAY_PAUSED||play_state==PLAY_LOADING||play_state==PLAY_ENDED))stop_play();if(arg!=PAGE_GAME)game_stop();if((arg==PAGE_FILES||arg==PAGE_GAME)&&mounted){list_offset=0;list_directory();}}
    else if(cmd==CMD_GAME_OPEN)game_open(arg);
    else if(cmd==CMD_GAME_STOP){game_stop();message=MSG_READY;list_directory();}
    else if(cmd==CMD_GAME_MODE){if(!(hw_read(HW_GAME_CTL)&1)){game_practice=!game_practice;hw_write(HW_GAME_CTL,game_practice?8:0);publish();}}
    else if(cmd==CMD_GAME_PAUSE){
        uint32_t g=hw_read(HW_GAME_CTL);
        // 读状态bit2是练习模式，写控制bit2却是清空；不能直接把状态字写回。
        if(g&1)hw_write(HW_GAME_CTL,1u|((g&2)?0u:2u)|((g&4)?8u:0u));
    }
    else if(cmd==CMD_OPEN)open_entry(arg);
    else if(cmd==CMD_UP){unsigned n=tlen(cwd);if(n>1){while(n>1&&cwd[n-1]!='/')n--;if(n>1)n--;cwd[n]=0;}list_offset=0;list_directory();}
    else if(cmd==CMD_LIST_PREV){list_offset=list_offset>=ROWS?list_offset-ROWS:0;list_directory();}
    else if(cmd==CMD_LIST_NEXT){if(list_offset+ROWS<total_entries)list_offset+=ROWS;list_directory();}
    else if(cmd==CMD_REFRESH){if(!mounted)mount_card();else list_directory();}
    else if(cmd==CMD_PLAY_STOP)stop_play();
    else if(cmd==CMD_PLAY_PAUSE){if(play_state==PLAY_RUNNING){play_state=PLAY_PAUSED;hw_write(HW_PLAY_CTL,3);}else if(play_state==PLAY_PAUSED){play_state=PLAY_RUNNING;hw_write(HW_PLAY_CTL,1);}publish();}
    else if(cmd==CMD_SEEK)seek_play(arg);
    else if(cmd==CMD_PREVIOUS||cmd==CMD_NEXT){
        // 遍历整个当前目录，跨越六行分页；跳过目录及不支持的格式。
        DIR dir;FILINFO info;unsigned index=0;int current=-1,previous=-1,found=-1;
        unsigned n=tlen(cwd);const TCHAR*base=selected+n+(n>1);
        if(f_opendir(&dir,cwd)==FR_OK){
            while(f_readdir(&dir,&info)==FR_OK&&info.fname[0]){
                if(!(info.fattrib&AM_DIR)&&suffix(info.fname,"wav")){
                    if(tlen(base)==tlen(info.fname)&&!memcmp(base,info.fname,(tlen(info.fname)+1)*sizeof(TCHAR))){current=index;if(cmd==CMD_PREVIOUS){found=previous;break;}}
                    else if(current>=0&&cmd==CMD_NEXT){found=index;break;}
                    previous=index;
                }index++;
            }f_closedir(&dir);
        }
        if(found>=0){list_offset=((unsigned)found/ROWS)*ROWS;list_directory();hw_write(HW_NAV,PAGE_FILES);open_entry((unsigned)found%ROWS);}
    }
}
void media_init(void){
    memset(ui,' ',256);for(unsigned i=64;i<68;i++)ui[i]=0;
    rec_state=REC_IDLE;play_state=PLAY_IDLE;message=MSG_NO_CARD;cwd[0]='/';cwd[1]=0;
    game_practice=1;hw_write(HW_GAME_CTL,12);
    hw_write(HW_REC_CTL,4);hw_write(HW_PLAY_CTL,4);hw_write(HW_PLAY_CTL,0);publish();mount_card();
}
void media_step(void){
    unsigned page=hw_read(HW_PAGE);
    usb_service();
    if(usb_exported){if(hw_read(HW_EVENTS)&255)event(hw_read(HW_EVENT_POP));if((int32_t)(hw_read(HW_MS)-next_publish)>=0)publish();return;}
    if(page!=PAGE_GAME&&(game_stream||(hw_read(HW_GAME_CTL)&1)))game_stop();
    if(page==PAGE_GAME&&game_stream)game_feed();
    if(page!=PAGE_PLAYER&&(play_state==PLAY_RUNNING||play_state==PLAY_PAUSED||play_state==PLAY_LOADING||play_state==PLAY_ENDED))stop_play();
    if(hw_read(HW_EVENTS)&255)event(hw_read(HW_EVENT_POP));
    if(rec_state==REC_RUNNING||rec_state==REC_PAUSED){
        uint32_t c=hw_read(HW_REC_COUNT);
        if(c&0x80000000u)finish_record(MSG_REC_OVERFLOW);
        else if((c&0x7fff)&&!drain_record()){hw_write(HW_REC_CTL,0);f_close(&stream);stream_open=0;mounted=0;rec_state=REC_ERROR;error(MSG_IO_ERROR);}
        else if(hw_read(HW_REC_SAMPLES)>=MAX_SAMPLES)finish_record(MSG_MAX_TIME);
        else if(hw_read(HW_MS)-last_sync>=1000){if(f_sync(&stream)!=FR_OK)finish_record(MSG_IO_ERROR);last_sync=hw_read(HW_MS);}
    }
    if(play_state==PLAY_LOADING||play_state==PLAY_RUNNING){
        if(hw_read(HW_PLAY_STATUS)&1){stop_play();play_state=PLAY_ERROR;error(MSG_PLAY_UNDERFLOW);}
        else{fill_playback();play_seconds=play_base+hw_read(HW_PLAY_FRAMES)/RATE;}
    }
    uint32_t now=hw_read(HW_MS);
    if(!usb_exported&&!mounted&&!stream_open&&(int32_t)(now-next_mount)>=0)mount_card();
    if((int32_t)(now-next_publish)>=0)publish();
}
