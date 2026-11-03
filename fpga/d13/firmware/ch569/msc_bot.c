#include "msc_bot.h"
#include <string.h>
// USB MSC Bulk-Only Transport，单LUN，512字节扇区。支持128GB卡的32位块地址。
// 不使用原示例直接挂在CH569 EMMC引脚上的SD驱动：卡仍由FPGA独占管理。
enum {CBW,RESPONSE,READING,WRITING,CSW,HALTED};
static unsigned state,at,size,pending,after,status,sense_key,sense_asc,halt,direction,epoch;
static uint32_t tag,residue,lba,left;
static uint8_t buffer[512],csw[13];
static uint32_t le32(const uint8_t*p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static uint32_t be32(const uint8_t*p){return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static void putle(uint8_t*p,uint32_t n){for(unsigned i=0;i<4;i++){p[i]=n;n>>=8;}}
static void putbe(uint8_t*p,uint32_t n){for(unsigned i=0;i<4;i++){p[3-i]=n;n>>=8;}}
static unsigned min(unsigned a,unsigned b){return a<b?a:b;}
static void fail(unsigned key,unsigned asc){sense_key=key;sense_asc=asc;status=1;state=CSW;at=0;if(residue)halt|=direction?2:1;}
static void phase(void){status=2;state=CSW;halt=3;}
static void response(unsigned n,unsigned allocation){size=min(min(n,allocation),residue);at=0;state=size?RESPONSE:CSW;if(!size&&residue)halt=2;}
void msc_reset(void){epoch++;state=CBW;at=size=pending=after=status=halt=0;residue=0;left=0;sense_key=sense_asc=0;}
int msc_idle(void){return state==CBW&&!pending;}
int msc_halted(void){return halt;}
void msc_clear_halt(unsigned endpoint){if(state!=HALTED)halt&=~endpoint;}
static void command(const uint8_t*p){
    if(le32(p)!=0x43425355u||p[13]||p[14]<1||p[14]>16||(p[12]&127)){state=HALTED;halt=3;return;}
    tag=le32(p+4);residue=le32(p+8);status=0;at=size=0;const uint8_t*c=p+15;unsigned op=c[0],in=p[12]&128;direction=in;
    unsigned min_cdb=(op==0x88||op==0x8a||op==0x9e)?16:(op==0xa0||op==0xa8||op==0xaa)?12:(op>=0x20&&op<=0x5f)?10:6;
    if(p[14]<min_cdb){fail(5,0x24);return;}
    // 数据方向不匹配不能被当成成功命令；要求主机执行BOT reset recovery。
    unsigned wants_out=op==0x2a||op==0xaa,wants_in=op==0x12||op==3||op==0x1a||op==0x5a||op==0x23||op==0x25||op==0x28||op==0xa8||op==0xa0;
    if(residue&&((wants_out&&in)||(wants_in&&!in))){phase();return;}
    memset(buffer,0,sizeof(buffer));
    if(op==0x12){
        if(c[1]&1){if(c[2]==0){buffer[1]=0;buffer[3]=3;buffer[4]=0;buffer[5]=0x80;buffer[6]=0x83;response(7,c[4]);}
            else if(c[2]==0x80){buffer[1]=0x80;buffer[3]=8;memcpy(buffer+4,"PIANO012",8);response(12,c[4]);}
            else if(c[2]==0x83){buffer[1]=0x83;buffer[3]=12;buffer[4]=2;buffer[5]=1;buffer[7]=8;memcpy(buffer+8,"PIANO012",8);response(16,c[4]);}
            else fail(5,0x24);
        }else {buffer[1]=0x80;buffer[2]=5;buffer[3]=2;buffer[4]=31;memcpy(buffer+8,"PIANO28 D12 DISK         1.00",28);response(36,c[4]);}return;
    }
    if(op==3){buffer[0]=0x70;buffer[2]=sense_key;buffer[7]=10;buffer[12]=sense_asc;response(18,c[4]);sense_key=sense_asc=0;return;}
    if(op==0xa0){buffer[3]=8;response(16,be32(c+6));return;}
    uint32_t blocks=disk_blocks();
    if(!blocks){fail(2,0x3a);return;}
    if(op==0x25){putbe(buffer,blocks-1);putbe(buffer+4,512);response(8,8);}
    else if(op==0x23){buffer[3]=8;putbe(buffer+4,blocks);buffer[8]=2;buffer[10]=2;response(12,((unsigned)c[7]<<8)|c[8]);}
    else if(op==0x1a||op==0x5a){unsigned ten=op==0x5a;buffer[ten?1:0]=ten?6:3;response(ten?8:4,ten?((unsigned)c[7]<<8)|c[8]:c[4]);}
    else if(op==0x28||op==0x2a||op==0xa8||op==0xaa){
        lba=be32(c+2);left=op==0xa8||op==0xaa?be32(c+6):((uint32_t)c[7]<<8)|c[8];
        if(left>0x7fffffu||residue!=left*512u){phase();return;}
        if(lba>=blocks||left>blocks-lba){fail(5,0x21);return;}
        if(!left){state=CSW;return;}
        state=wants_out?WRITING:READING;size=0;
    }else if(op==0x35){unsigned generation=epoch;int ok=block_sync();if(generation!=epoch)return;if(ok)state=CSW;else fail(3,0x0c);}
    else if(op==0x1b){if((c[4]&3)==2){unsigned generation=epoch;int ok=block_sync();if(generation!=epoch)return;if(!ok){fail(3,0x0c);return;}disk_eject();}state=CSW;}
    else if(op==0||op==0x1e||(op==0x2f&&!(c[1]&2))){if(residue)phase();else state=CSW;}
    else fail(5,0x20);
}
void msc_out(const uint8_t*p,unsigned n){
    if(state==HALTED)return;
    if(state==CBW){if(n!=31){state=HALTED;halt=3;return;}command(p);return;}
    if(state!=WRITING||n>512-at||n>residue){phase();return;}
    memcpy(buffer+at,p,n);at+=n;residue-=n;
    if(at==512){unsigned generation=epoch;int ok=block_write(lba,buffer);if(generation!=epoch)return;if(!ok){fail(3,0x0c);return;}at=0;lba++;if(--left==0){ok=block_sync();if(generation!=epoch)return;if(ok)state=CSW;else fail(3,0x0c);}}
}
int msc_in(uint8_t*out,unsigned max){
    if(pending||halt||state==CBW||state==WRITING||state==HALTED)return -1;
    if(state==READING&&size==0){unsigned generation=epoch;int ok=block_read(lba,buffer);if(generation!=epoch)return -1;if(!ok){fail(3,0x11);return -1;}else{size=512;at=0;}}
    if(state==CSW){putle(csw,0x53425355);putle(csw+4,tag);putle(csw+8,residue);csw[12]=status;memcpy(out,csw,13);pending=1;after=CBW;return 13;}
    unsigned n=min(size-at,max);memcpy(out,buffer+at,n);at+=n;residue-=n;
    after=state;
    if(at==size){if(state==READING){lba++;left--;size=0;after=left?READING:CSW;}else after=CSW;}
    pending=1;return n;
}
void msc_tx_complete(void){if(pending){pending=0;state=after;}}
