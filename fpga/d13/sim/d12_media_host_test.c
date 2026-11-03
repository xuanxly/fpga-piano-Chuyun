// Native integration test: real FatFs and Helix, sparse virtual SD; never opens a physical disk.
#include "media_hw.h"
#include "ff.h"
#include "diskio.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
typedef struct Sector{uint32_t key;unsigned char data[512];struct Sector*next;}Sector;
static Sector*buckets[131071];static unsigned card_sectors=250000000,card_present=1,write_fault;
static uint32_t regs[2048],ui[68],events[64],event_r,event_w;
static uint32_t fifo[MEDIA_FIFO_WORDS],wr,rd,count,captured,rec_ctl,play_ctl,played,pending,first;
static unsigned char valid[MEDIA_FIFO_WORDS];static unsigned last_valid;
static uint64_t output_frames,output_energy;static uint32_t output_crc;
static unsigned checks,ch_ready,ch_allow,game_count;
static uint32_t game_time,game_mask,game_duration,game_masks[64];
static unsigned char ch_rx[2048],ch_tx[2048];static unsigned ch_r,ch_w,ch_t;
static uint16_t crc16(const unsigned char*p,unsigned n){uint16_t c=0xffff;while(n--){c^=(uint16_t)*p++<<8;for(unsigned i=0;i<8;i++)c=(c<<1)^((c&0x8000)?0x1021:0);}return c;}

#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"FAIL line %d: %s flags=%08x page=%u\n",__LINE__,#x,ui[64],regs[1]);exit(1);}}while(0)
static Sector*sector(uint32_t key,int create){unsigned h=key%131071;Sector*p=buckets[h];while(p&&p->key!=key)p=p->next;if(!p&&create){p=calloc(1,sizeof(*p));assert(p);p->key=key;p->next=buckets[h];buckets[h]=p;}return p;}
DSTATUS disk_initialize(BYTE d){return d||!card_present?STA_NOINIT:0;}
DSTATUS disk_status(BYTE d){return disk_initialize(d);}
DRESULT disk_read(BYTE d,BYTE*b,LBA_t at,UINT n){if(d||!card_present)return RES_NOTRDY;if(at+n>card_sectors)return RES_PARERR;while(n--){Sector*p=sector(at++,0);if(p)memcpy(b,p->data,512);else memset(b,0,512);b+=512;}return RES_OK;}
DRESULT disk_write(BYTE d,const BYTE*b,LBA_t at,UINT n){if(d||!card_present||write_fault)return RES_ERROR;if(at+n>card_sectors)return RES_PARERR;while(n--){Sector*p=sector(at,0);unsigned any=0;for(unsigned i=0;i<512;i++)any|=b[i];if(any||p){if(!p)p=sector(at,1);memcpy(p->data,b,512);}b+=512;at++;}return RES_OK;}
DRESULT disk_ioctl(BYTE d,BYTE c,void*b){if(d||!card_present)return RES_NOTRDY;if(c==GET_SECTOR_COUNT)*(LBA_t*)b=card_sectors;else if(c==GET_SECTOR_SIZE)*(WORD*)b=512;else if(c==GET_BLOCK_SIZE)*(DWORD*)b=128;else if(c!=CTRL_SYNC)return RES_PARERR;return RES_OK;}
void media_heap_reset(void){}size_t media_heap_used(void){return 0;}
uint32_t hw_read(unsigned off){switch(off){
case HW_USB_STATUS:return ch_ready|(ch_allow<<1);
case HW_USB_RX_COUNT:return ch_w-ch_r;case HW_USB_RX:return ch_rx[ch_r++];case HW_USB_TX_FREE:return 512;
case HW_GAME_CTL:return ((32-game_count)<<16)|(regs[off/4]&3)|((regs[off/4]&8)>>1);
case HW_EVENTS:return event_w-event_r;case HW_EVENT_POP:return events[event_r++%64];case HW_REC_COUNT:return count;case HW_REC_SAMPLES:return captured;case HW_REC_LAST_VALID:return last_valid;case HW_REC_POP:{assert(count);uint32_t v=fifo[rd];last_valid=valid[rd];rd=(rd+1)%MEDIA_FIFO_WORDS;count--;return v;}case HW_PLAY_FREE:return MEDIA_FIFO_WORDS-count;case HW_PLAY_FRAMES:return played;case HW_PLAY_STATUS:return 0;default:return regs[off/4];}}
static void reset_fifo(void){wr=rd=count=captured=played=pending=0;rec_ctl=play_ctl=0;}
void hw_write(unsigned off,uint32_t v){
 if(off==HW_USB_CTL)ch_allow=v&1;
 else if(off==HW_USB_TX){assert(ch_t<sizeof(ch_tx));ch_tx[ch_t++]=v;}
 else if(off==HW_GAME_CTL){regs[off/4]=v&11;if(v&4)game_count=0;}
 else if(off==HW_GAME_TIME)game_time=v;
 else if(off==HW_GAME_MASK)game_mask=v;
 else if(off==HW_GAME_DURATION)game_duration=v;
 else if(off==HW_GAME_COMMIT){assert(game_count<32);game_masks[game_count++]=game_mask;}
 else if(off==HW_REC_CTL){if(v&4)reset_fifo();else if((!(v&1)||(v&2))&&pending){assert(count<MEDIA_FIFO_WORDS);fifo[wr]=first;valid[wr]=1;wr=(wr+1)%MEDIA_FIFO_WORDS;count++;pending=0;}rec_ctl=v&3;}
 else if(off==HW_PLAY_CTL){if(v&4)reset_fifo();play_ctl=v&3;}
 else if(off==HW_PLAY_PUSH){assert(count<MEDIA_FIFO_WORDS);fifo[wr]=v;wr=(wr+1)%MEDIA_FIFO_WORDS;count++;}
 else if(off==HW_NAV)regs[HW_PAGE/4]=v;
 else if(off>=HW_UI_BASE&&off<HW_UI_BASE+272)ui[(off-HW_UI_BASE)/4]=v;
 else regs[off/4]=v;
}
static void step(void){regs[0]++;media_step();}
static void event(unsigned c,unsigned a){events[event_w++%64]=c<<24|a;step();}
static void page(unsigned p){regs[1]=p;event(CMD_PAGE,p);}
static unsigned recstate(void){return ui[64]>>2&7;}static unsigned playstate(void){return ui[64]>>5&7;}
static int16_t sample_at(unsigned n){return (int16_t)((n*71u)^0x5a5a);}
static void feed(unsigned source,unsigned n){for(unsigned i=0;i<n;i++)if(rec_ctl==1&&captured<14400000){unsigned s=(uint16_t)sample_at(source+i);if(!pending){first=s;pending=1;}else{assert(count<MEDIA_FIFO_WORDS);fifo[wr]=first|(s<<16);valid[wr]=2;wr=(wr+1)%MEDIA_FIFO_WORDS;count++;pending=0;}captured++;}}
static void consume(unsigned n){while(n--&&count&&play_ctl==1&&regs[1]==PAGE_PLAYER){uint32_t v=fifo[rd];rd=(rd+1)%MEDIA_FIFO_WORDS;count--;played++;output_frames++;int l=(int16_t)v,r=(int16_t)(v>>16);output_energy+=(uint64_t)(l*l)+(uint64_t)(r*r);output_crc=output_crc*16777619u^v;}}
static void wide(TCHAR*d,const char*s){while((*d++=(unsigned char)*s++));}
static void write_file(const char*name,const void*p,unsigned n){TCHAR w[256];wide(w,name);FIL f;UINT done;CHECK(f_open(&f,w,FA_CREATE_ALWAYS|FA_WRITE)==FR_OK);CHECK(f_write(&f,p,n,&done)==FR_OK&&done==n);CHECK(f_close(&f)==FR_OK);}
static void import_file(const char*name,const char*host){FILE*f=fopen(host,"rb");assert(f);fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);void*p=malloc(n);assert(p&&fread(p,1,n,f)==(size_t)n);fclose(f);write_file(name,p,n);free(p);}
static int row(const char*s){for(unsigned i=0;i<(ui[66]>>16&255);i++)if(!memcmp((char*)ui+i*32,s,strlen(s)))return i;return -1;}
static unsigned find(const char*s){page(PAGE_FILES);event(CMD_LIST_PREV,0);event(CMD_LIST_PREV,0);event(CMD_LIST_PREV,0);for(unsigned tries=0;tries<8;tries++){int r=row(s);if(r>=0)return r;event(CMD_LIST_NEXT,0);}fprintf(stderr,"Missing %s\n",s);exit(1);}
static void verify_record(const char*name,unsigned samples,unsigned split,unsigned gap){TCHAR w[64];wide(w,name);FIL f;UINT got;unsigned char b[2048];CHECK(f_open(&f,w,FA_READ)==FR_OK);CHECK(f_size(&f)==44+samples*2);CHECK(f_read(&f,b,44,&got)==FR_OK&&got==44);CHECK(!memcmp(b,"RIFF",4)&&!memcmp(b+36,"data",4));unsigned size=b[40]|b[41]<<8|b[42]<<16|b[43]<<24;CHECK(size==samples*2);for(unsigned at=0;at<samples;){unsigned n=samples-at;if(n>1024)n=1024;CHECK(f_read(&f,b,n*2,&got)==FR_OK&&got==n*2);for(unsigned i=0;i<n;i++){int16_t s=b[i*2]|(unsigned)b[i*2+1]<<8;CHECK(s==sample_at(at+i+((at+i)>=split?gap:0)));}at+=n;}CHECK(f_close(&f)==FR_OK);}
static void usb_exchange(unsigned op,const void*payload,unsigned n,unsigned corrupt){
 ch_r=ch_w=ch_t=0;ch_rx[ch_w++]=0xd5;ch_rx[ch_w++]=0x12;ch_rx[ch_w++]=op;ch_rx[ch_w++]=0x55;ch_rx[ch_w++]=n;ch_rx[ch_w++]=n>>8;
 if(n){memcpy(ch_rx+ch_w,payload,n);ch_w+=n;}uint16_t crc=crc16(ch_rx,ch_w);if(corrupt)crc^=1;ch_rx[ch_w++]=crc;ch_rx[ch_w++]=crc>>8;
 for(unsigned i=0;i<8;i++)step();
}
static void usb_request(unsigned op,const void*payload,unsigned n){
 usb_exchange(op,payload,n,0);
 CHECK(ch_t>=9&&ch_tx[2]==(op|128)&&ch_tx[3]==0x55);
 CHECK(crc16(ch_tx,ch_t-2)==(ch_tx[ch_t-2]|ch_tx[ch_t-1]<<8));
}
int main(int argc,char**argv){
 CHECK(argc==4);MKFS_PARM fmt={0};fmt.fmt=atoi(argv[1])?FM_EXFAT:FM_FAT32;fmt.n_fat=1;fmt.align=128;fmt.au_size=32768;
 unsigned char work[4096];CHECK(f_mkfs((const TCHAR[]){0},&fmt,work,sizeof(work))==FR_OK);
 media_init();CHECK(ui[64]&1);CHECK(!!(ui[64]&2)==!!atoi(argv[1]));
 write_file("/notes.txt","not audio",9);import_file("/one.wav",argv[2]);write_file("/unsupported.mp3","not decoder data",16);
 for(unsigned i=0;i<7;i++){char n[32];sprintf(n,"/other%u.txt",i);write_file(n,"x",1);}import_file("/two.wav",argv[3]);
 TCHAR folder[64];wide(folder,"/folder");CHECK(f_mkdir(folder)==FR_OK);write_file("/folder/inside.txt","ok",2);
 wide(folder,"/SONGS");CHECK(f_mkdir(folder)==FR_OK);
 const char*chart="PIANO28,1\n0,400,C3+E3+G3\n500,100,D4\n";
 write_file("/SONGS/FIRST.CSV",chart,strlen(chart));const char*bad_chart="PIANO28,1\n0,400,C3\n10,100,C3\n";write_file("/SONGS/BAD.CSV",bad_chart,strlen(bad_chart));
 page(PAGE_RECORDER);event(CMD_RECORD,0);CHECK(recstate()==REC_RUNNING);
 for(unsigned i=0;i<10001;i+=1000){unsigned n=10001-i;if(n>1000)n=1000;feed(i,n);step();}
 event(CMD_REC_PAUSE,0);CHECK(recstate()==REC_PAUSED);feed(10001,999);step();CHECK(captured==10001);
 page(PAGE_HOME);CHECK(recstate()==REC_PAUSED);event(CMD_REC_PAUSE,0);CHECK(recstate()==REC_RUNNING);
 for(unsigned i=0;i<10003;i+=1000){unsigned n=10003-i;if(n>1000)n=1000;feed(11000+i,n);step();}
 event(CMD_RECORD,0);CHECK(recstate()==REC_IDLE);verify_record("/REC0001.WAV",20004,10001,999);
 page(PAGE_RECORDER);event(CMD_RECORD,0);CHECK(recstate()==REC_RUNNING);unsigned wavrow=find("one.wav");event(CMD_OPEN,wavrow);CHECK(recstate()==REC_RUNNING&&ui[64]>>16==MSG_END_REC_FIRST);
 for(unsigned i=0;i<14400000;i+=1024){unsigned n=14400000-i;if(n>1024)n=1024;feed(i,n);step();}
 for(unsigned i=0;i<40&&recstate()!=REC_IDLE;i++)step();CHECK(recstate()==REC_IDLE);verify_record("/REC0002.WAV",14400000,14400000,0);
 const char*tracks[]={"one.wav","two.wav"};
 for(unsigned t=0;t<2;t++){
  unsigned r=find(tracks[t]);output_frames=output_energy=output_crc=0;event(CMD_OPEN,r);CHECK(regs[1]==PAGE_PLAYER);step();CHECK(playstate()==PLAY_RUNNING);
  consume(5000);step();event(CMD_PLAY_PAUSE,0);CHECK(playstate()==PLAY_PAUSED);unsigned before=count;consume(1000);CHECK(count==before);event(CMD_PLAY_PAUSE,0);
  event(CMD_SEEK,500);for(unsigned i=0;i<5;i++)step();CHECK(playstate()==PLAY_RUNNING||playstate()==PLAY_ENDED);
  for(unsigned i=0;i<1000&&playstate()==PLAY_RUNNING;i++){consume(1000);step();}
  CHECK(playstate()==PLAY_ENDED);CHECK(output_frames>20000&&output_energy>100000000);
 }
 page(PAGE_HOME);CHECK(playstate()==PLAY_IDLE&&play_ctl==0&&count==0);
 event(CMD_OPEN,find("unsupported.mp3"));CHECK(ui[64]>>16==MSG_UNSUPPORTED);
 page(PAGE_GAME);CHECK(row("FIRST.CSV")>=0&&row("notes.txt")<0);event(CMD_GAME_OPEN,row("FIRST.CSV"));
 CHECK(game_count==3&&game_masks[0]==21&&game_masks[1]==(1u<<8)&&game_masks[2]==0x80000000u);
 CHECK(hw_read(HW_GAME_CTL)&1);event(CMD_GAME_STOP,0);CHECK(!(hw_read(HW_GAME_CTL)&1));
 event(CMD_GAME_OPEN,row("FIRST.CSV"));event(CMD_GAME_PAUSE,0);
 CHECK((hw_read(HW_GAME_CTL)&7)==7&&game_count==3);event(CMD_GAME_PAUSE,0);CHECK((hw_read(HW_GAME_CTL)&7)==5&&game_count==3);event(CMD_GAME_STOP,0);
 event(CMD_GAME_OPEN,row("BAD.CSV"));CHECK(ui[64]>>16==MSG_BAD_CHART&&!(hw_read(HW_GAME_CTL)&1));
 page(PAGE_FILES);event(CMD_USB_DISK,0);CHECK(ui[64]>>16==MSG_USB_WAIT); // 原厂固件不能取得卡
 ch_ready=1;usb_exchange(1,"PIANO12!",8,1);CHECK(!ch_allow&&ch_t==0&&(ui[64]&1));
 usb_exchange(1,"WRONGSIG",8,0);CHECK(!ch_allow&&ch_t==0&&(ui[64]&1));
 usb_request(1,"PIANO12!",8);CHECK(ch_allow);
 event(CMD_USB_DISK,0);CHECK(ui[64]>>16==MSG_USB_EXPORTED&&!(ui[64]&1));
 usb_request(2,0,0);CHECK(ch_tx[6]==1);
 unsigned char payload[516];uint32_t lba=200000000u;for(unsigned i=0;i<4;i++)payload[i]=lba>>(i*8);for(unsigned i=0;i<512;i++)payload[i+4]=i*13u;
 usb_request(4,payload,516);CHECK(ch_tx[6]==0);usb_request(3,payload,4);CHECK(ch_t==521&&ch_tx[6]==0&&!memcmp(ch_tx+7,payload+4,512));
 payload[4]^=255;usb_exchange(4,payload,516,1);CHECK(ch_t==0);payload[4]^=255;
 usb_request(3,payload,4);CHECK(ch_tx[6]==0&&!memcmp(ch_tx+7,payload+4,512));
 event(CMD_RECORD,0);CHECK(recstate()==REC_IDLE);event(CMD_GAME_OPEN,0);CHECK(!(hw_read(HW_GAME_CTL)&1));
 event(CMD_USB_DISK,0);CHECK(ui[64]>>16==MSG_USB_UNPLUG);usb_request(5,0,0);CHECK(ch_tx[6]==0);usb_request(6,0,0);
 for(unsigned i=0;i<300;i++)step();CHECK(ui[64]&1);verify_record("/REC0001.WAV",20004,10001,999);
 // 在导出期间失去MCU READY：停止协议，卡同步并重新挂载，不继续使用陈旧目录缓存。
 event(CMD_USB_DISK,0);CHECK(ui[64]>>16==MSG_USB_EXPORTED);ch_ready=0;for(unsigned i=0;i<300;i++)step();CHECK(ui[64]&1&&!ch_allow);
 // D13效果页保持录音；进入验证页保存录音，避免测试音污染用户录制。
 page(PAGE_RECORDER);event(CMD_RECORD,0);CHECK(recstate()==REC_RUNNING);feed(0,1234);step();
 page(PAGE_EFFECTS);CHECK(recstate()==REC_RUNNING);page(PAGE_VERIFY);CHECK(recstate()==REC_IDLE);verify_record("/REC0003.WAV",1234,1234,0);
 page(PAGE_RECORDER);event(CMD_RECORD,0);CHECK(recstate()==REC_RUNNING);write_fault=1;feed(0,2000);step();CHECK(recstate()==REC_ERROR&&rec_ctl==0);
 printf("PASS D12 media_host: %s128GB sparse, %u checks; five-minute record/WAV/resample/CSV validity/USB identity+CRC/read/write/ownership/eject/recovery\n",atoi(argv[1])?"exFAT":"FAT32",checks);
 return 0;
}
