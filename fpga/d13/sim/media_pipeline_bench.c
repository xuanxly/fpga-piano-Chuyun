// Actual media_service.c playback scheduler + decoder + resampler. Memory-backed
// f_read isolates the CPU/audio deadline; SD protocol is checked independently.
#include "media_hw.h"
#include "ff.h"
#include <string.h>
#include "media_fixture.h"
uint32_t hw_read(unsigned o){return *(volatile uint32_t*)(MEDIA_BASE+o);}
void hw_write(unsigned o,uint32_t v){*(volatile uint32_t*)(MEDIA_BASE+o)=v;}
FRESULT f_read(FIL*f,void*p,UINT n,UINT*got){unsigned remaining=sizeof(fixture)-f->fptr;if(n>remaining)n=remaining;memcpy(p,fixture+f->fptr,n);f->fptr+=n;*got=n;return FR_OK;}
FRESULT f_lseek(FIL*f,FSIZE_t n){if(n>sizeof(fixture))return FR_INT_ERR;f->fptr=n;return FR_OK;}
FRESULT f_close(FIL*f){(void)f;return FR_OK;}
#include "../firmware/media_service.c"
int main(void){
 stream.obj.objsize=sizeof(fixture);stream.fptr=0;stream_open=1;kind=2;
 hw_write(HW_BOOT_STATUS,0xd9b10001);if(!mp3_open()){hw_write(HW_BOOT_STATUS,0xd9b1ee01);for(;;){}}
 hw_write(HW_PLAY_CTL,4);play_state=PLAY_LOADING;
 unsigned iterations=0;
 while(play_state==PLAY_LOADING||play_state==PLAY_RUNNING){
  if(hw_read(HW_PLAY_STATUS)){hw_write(HW_BOOT_STATUS,0xd9b1ee02);for(;;){}}
  fill_playback();iterations++;
 }
 hw_write(HW_UI_BASE,iterations);hw_write(HW_BOOT_STATUS,0xd9b1d00d);for(;;){}
}
