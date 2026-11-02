// 连续200帧测试：真实SD驱动/SPI读卡 + 实际播放调度/MP3/重采样，仍不访问实体卡。
#include "media_hw.h"
#include "ff.h"
#include "diskio.h"
#include <string.h>
#include "media_fixture_size.h"
uint32_t hw_read(unsigned o){return *(volatile uint32_t*)(MEDIA_BASE+o);}
void hw_write(unsigned o,uint32_t v){*(volatile uint32_t*)(MEDIA_BASE+o)=v;}
static unsigned char sector_buffer[512];
FRESULT f_read(FIL*f,void*p,UINT n,UINT*got){
 unsigned char*out=p;unsigned remaining=FIXTURE_BYTES*10u-f->fptr;if(n>remaining)n=remaining;*got=0;
 while(n){unsigned offset=f->fptr%512,chunk=512-offset;if(chunk>n)chunk=n;
  if(!offset&&n>=512){unsigned blocks=n/512;if(disk_read(0,out,f->fptr/512,blocks)!=RES_OK)return FR_DISK_ERR;chunk=blocks*512;}
  else {if(disk_read(0,sector_buffer,f->fptr/512,1)!=RES_OK)return FR_DISK_ERR;memcpy(out,sector_buffer+offset,chunk);}
  out+=chunk;f->fptr+=chunk;*got+=chunk;n-=chunk;
 }return FR_OK;
}
FRESULT f_lseek(FIL*f,FSIZE_t n){if(n>FIXTURE_BYTES*10u)return FR_INT_ERR;f->fptr=n;return FR_OK;}
FRESULT f_close(FIL*f){(void)f;return FR_OK;}
#include "../firmware/media_service.c"
int main(void){
 hw_write(HW_BOOT_STATUS,0xd9b20001);
 if(disk_initialize(0)){hw_write(HW_BOOT_STATUS,0xd9b2ee01);for(;;){}}
 stream.obj.objsize=FIXTURE_BYTES*10u;stream.fptr=0;stream_open=1;kind=2;
 if(!mp3_open()){hw_write(HW_BOOT_STATUS,0xd9b2ee02);for(;;){}}
 hw_write(HW_PLAY_CTL,4);play_state=PLAY_LOADING;
 while(play_state==PLAY_LOADING||play_state==PLAY_RUNNING){
  if(hw_read(HW_PLAY_STATUS)){hw_write(HW_BOOT_STATUS,0xd9b2ee03);for(;;){}}
  fill_playback();
 }
 hw_write(HW_BOOT_STATUS,play_state==PLAY_ENDED?0xd9b2d00d:0xd9b2ee04);for(;;){}
}
