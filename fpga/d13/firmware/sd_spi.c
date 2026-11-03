#include "media_hw.h"
#include "ff.h"
#include "diskio.h"
#include <stdint.h>
// SDXC采用块寻址；初始化低于400kHz，成功后12.5MHz。所有等待有界，不自动格式化卡。
static DSTATUS status=STA_NOINIT;
static uint32_t sectors;
static int block_addressed;
static unsigned divider=64;
static void select_card(int selected){hw_write(HW_SPI_CFG,divider|((uint32_t)!selected<<16));}
static uint8_t exchange(uint8_t b){
    unsigned guard=100000;
    while((hw_read(HW_SPI_RX)&1)&&--guard){}
    if(!guard){status=STA_NOINIT;return 255;}
    hw_write(HW_SPI_TX,b);guard=100000;
    while((hw_read(HW_SPI_RX)&1)&&--guard){}
    if(!guard){status=STA_NOINIT;return 255;}
    return (uint8_t)(hw_read(HW_SPI_RX)>>8);
}
static int wait_ready(unsigned timeout){uint32_t start=hw_read(HW_MS);do{if(exchange(255)==255)return 1;}while(hw_read(HW_MS)-start<timeout);return 0;}
static uint8_t crc7(uint8_t*data,unsigned n){unsigned crc=0;while(n--){unsigned b=*data++;for(unsigned i=0;i<8;i++){crc<<=1;if((b^crc)&128)crc^=9;b<<=1;}}return(uint8_t)((crc<<1)|1);}
static uint16_t crc16_step(uint16_t c,uint8_t b){
    static const uint16_t table[16]={0x0000,0x1021,0x2042,0x3063,0x4084,0x50a5,0x60c6,0x70e7,0x8108,0x9129,0xa14a,0xb16b,0xc18c,0xd1ad,0xe1ce,0xf1ef};
    c=(uint16_t)((c<<4)^table[(c>>12)^(b>>4)]);
    return(uint16_t)((c<<4)^table[(c>>12)^(b&15)]);
}
static uint8_t command(unsigned cmd,uint32_t arg){
    uint8_t p[6]={0x40|cmd,arg>>24,arg>>16,arg>>8,arg,0};p[5]=crc7(p,5);
    if(cmd!=12&&!wait_ready(500))return 255;
    for(unsigned i=0;i<6;i++)exchange(p[i]);if(cmd==12)exchange(255);
    for(unsigned i=0;i<16;i++){uint8_t r=exchange(255);if(!(r&128))return r;}return 255;
}
static int read_block(uint8_t*data,unsigned n){
    uint32_t start=hw_read(HW_MS);uint8_t token;
    do{token=exchange(255);if(token!=255)break;}while(hw_read(HW_MS)-start<500);
    if(token!=254)return 0;
    uint16_t crc=0;for(unsigned i=0;i<n;i++){data[i]=exchange(255);crc=crc16_step(crc,data[i]);}
    uint16_t card=(uint16_t)exchange(255)<<8;card|=exchange(255);return card==crc;
}
static int write_block(const uint8_t*data,uint8_t token){
    if(!wait_ready(500))return 0;exchange(token);
    if(token==253)return wait_ready(500);
    uint16_t crc=0;for(unsigned i=0;i<512;i++){exchange(data[i]);crc=crc16_step(crc,data[i]);}
    exchange(crc>>8);exchange(crc);
    uint8_t r=exchange(255);return (r&31)==5&&wait_ready(500);
}
DSTATUS disk_status(BYTE pdrv){return pdrv?STA_NOINIT:status;}
DSTATUS disk_initialize(BYTE pdrv){
    if(pdrv)return STA_NOINIT;
    status=STA_NOINIT;divider=64;select_card(0);for(unsigned i=0;i<12;i++)exchange(255);select_card(1);
    if(command(0,0)!=1)goto fail;
    uint8_t r=command(8,0x1aa);block_addressed=0;
    if(r==1){uint8_t v[4];for(unsigned i=0;i<4;i++)v[i]=exchange(255);if(v[2]!=1||v[3]!=0xaa)goto fail;}
    else if(r!=5)goto fail;
    uint32_t start=hw_read(HW_MS);
    do{if(command(55,0)>1)goto fail;r=command(41,0x40000000u);if(r==0)break;}while(hw_read(HW_MS)-start<2000);
    if(r!=0||command(58,0)!=0)goto fail;
    uint8_t ocr=exchange(255);block_addressed=!!(ocr&64);for(unsigned i=0;i<3;i++)exchange(255);
    if(!block_addressed&&command(16,512)!=0)goto fail;
    uint8_t csd[16];if(command(9,0)!=0||!read_block(csd,16))goto fail;
    if((csd[0]>>6)==1){uint32_t c=((uint32_t)(csd[7]&63)<<16)|((uint32_t)csd[8]<<8)|csd[9];sectors=(c+1)*1024u;}
    else {unsigned n=(csd[5]&15)+((csd[10]&128)>>7)+((csd[9]&3)<<1)+2;uint32_t c=((csd[6]&3)<<10)|(csd[7]<<2)|(csd[8]>>6);if(n<9||n>31)goto fail;sectors=(c+1)<<(n-9);}
    divider=2;select_card(0);exchange(255);status=0;return status;
fail:select_card(0);exchange(255);return status;
}
DRESULT disk_read(BYTE pdrv,BYTE*buff,LBA_t sector,UINT count){
    if(pdrv||!count||sector>=sectors||count>sectors-sector)return RES_PARERR;if(status)return RES_NOTRDY;
    select_card(1);uint32_t addr=block_addressed?(uint32_t)sector:(uint32_t)sector*512;
    int ok=command(count>1?18:17,addr)==0;UINT n=count;
    while(ok&&n){ok=read_block(buff,512);buff+=512;n--;}
    if(count>1){if(command(12,0)!=0||!wait_ready(500))ok=0;}
    select_card(0);exchange(255);if(!ok){status=STA_NOINIT;return RES_ERROR;}return RES_OK;
}
DRESULT disk_write(BYTE pdrv,const BYTE*buff,LBA_t sector,UINT count){
    if(pdrv||!count||sector>=sectors||count>sectors-sector)return RES_PARERR;if(status)return RES_NOTRDY;
    select_card(1);uint32_t addr=block_addressed?(uint32_t)sector:(uint32_t)sector*512;
    int ok=command(count>1?25:24,addr)==0;UINT n=count;
    while(ok&&n){ok=write_block(buff,count>1?252:254);buff+=512;n--;}
    if(count>1&&!write_block(0,253))ok=0;
    select_card(0);exchange(255);if(!ok){status=STA_NOINIT;return RES_ERROR;}return RES_OK;
}
DRESULT disk_ioctl(BYTE pdrv,BYTE cmd,void*buff){
    if(pdrv)return RES_PARERR;if(status)return RES_NOTRDY;
    if(cmd==GET_SECTOR_COUNT){*(LBA_t*)buff=sectors;return RES_OK;}
    if(cmd==GET_SECTOR_SIZE){*(WORD*)buff=512;return RES_OK;}
    if(cmd==GET_BLOCK_SIZE){*(DWORD*)buff=128;return RES_OK;}
    if(cmd==CTRL_SYNC){select_card(1);int ok=wait_ready(500);select_card(0);return ok?RES_OK:RES_ERROR;}
    return RES_PARERR;
}
