#include "msc_bot.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint8_t disk[8][512],cbw[31],in[512];static unsigned reads,writes,syncs,ejects,fail_io,reset_io;
uint32_t disk_blocks(void){return 250000000u;} // 128GB级容量，末尾扇区不在小型模拟盘中。
int block_read(uint32_t lba,uint8_t*p){reads++;if(reset_io){msc_reset();return 0;}if(fail_io)return 0;for(unsigned i=0;i<512;i++)p[i]=lba<8?disk[lba][i]:(uint8_t)(lba+i);return 1;}
int block_write(uint32_t lba,const uint8_t*p){writes++;if(reset_io){msc_reset();return 0;}if(fail_io)return 0;if(lba<8)memcpy(disk[lba],p,512);return 1;}
int block_sync(void){syncs++;return !fail_io;}
void disk_eject(void){ejects++;}
static uint32_t le32(const uint8_t*p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put(uint8_t*p,uint32_t n){for(unsigned i=0;i<4;i++){p[i]=n;n>>=8;}}
static void command(unsigned op,unsigned n,unsigned dir){memset(cbw,0,31);put(cbw,0x43425355);put(cbw+4,0x12345678);put(cbw+8,n);cbw[12]=dir?128:0;cbw[14]=op>=0xa0?12:op>=0x20?10:6;cbw[15]=op;}
static void submit(void){msc_out(cbw,31);}
static void csw(unsigned status,unsigned residue){int n=msc_in(in,512);assert(n==13&&le32(in)==0x53425355&&le32(in+4)==0x12345678&&le32(in+8)==residue&&in[12]==status);msc_tx_complete();assert(msc_idle());}
int main(void){
    msc_reset();command(0x12,96,1);cbw[19]=96;submit();assert(msc_in(in,512)==36&&!memcmp(in+8,"PIANO28",7));assert(msc_in(in,512)<0);msc_tx_complete();csw(0,60);
    command(0x25,8,1);submit();assert(msc_in(in,64)==8&&in[4]==0&&in[5]==0&&in[6]==2&&in[7]==0);msc_tx_complete();csw(0,0);
    command(0x12,36,1);cbw[19]=0;submit();assert(msc_halted()==2);msc_clear_halt(2);csw(0,36);
    for(unsigned i=0;i<512;i++)in[i]=(uint8_t)(i*7);
    command(0x2a,1024,0);cbw[22]=2;cbw[23]=0;cbw[24]=2;submit();
    // CDB bytes: opcode+LBA bytes2..5 = indexes17..20, transfer7..8=index22..23.
    msc_reset();command(0x2a,1024,0);cbw[20]=2;cbw[23]=2;submit();
    for(unsigned block=0;block<2;block++)for(unsigned p=0;p<8;p++)msc_out(in,64);
    csw(0,0);assert(writes==2&&syncs==1&&disk[2][15]==105&&disk[3][15]==105);
    command(0x28,1024,1);cbw[20]=2;cbw[23]=2;submit();
    for(unsigned p=0;p<16;p++){assert(msc_in(in,64)==64&&in[15]==105);msc_tx_complete();}csw(0,0);assert(reads==2);
    command(0x28,512,1);memset(cbw+17,255,4);cbw[23]=1;submit();assert(msc_halted()==2);assert(msc_in(in,512)<0);msc_clear_halt(2);csw(1,512);
    command(3,18,1);cbw[19]=18;submit();assert(msc_in(in,512)==18&&in[2]==5&&in[12]==0x21);msc_tx_complete();csw(0,0);
    command(0x28,512,0);cbw[23]=1;submit();assert(msc_halted()==3);msc_clear_halt(3);csw(2,512);
    command(0,0,0);cbw[0]=0;submit();assert(msc_halted()==3);msc_clear_halt(3);assert(msc_halted()==3);msc_reset();assert(msc_idle());
    command(0x35,0,0);submit();csw(0,0);command(0x1b,0,0);cbw[19]=2;submit();csw(0,0);assert(ejects==1);
    fail_io=1;command(0x28,512,1);cbw[23]=1;submit();assert(msc_in(in,512)<0&&msc_halted()==2);msc_clear_halt(2);csw(1,512);
    fail_io=0;reset_io=1;command(0x28,512,1);cbw[23]=1;submit();assert(msc_in(in,512)<0&&msc_idle());reset_io=0;
    // Fuzz invalid CBWs and phase lengths: all remain bounded and recover with class reset.
    for(unsigned i=0;i<10000;i++){command(0x28,i,1);cbw[23]=1;submit();msc_reset();}
    puts("PASS MSC BOT: inquiry capacity128GB read/write64/512 multi-sector CSW residue sense halt reset sync eject IOfailure reset-duringIO fuzz10000");
}
