#include "media_hw.h"
#include "ff.h"
#include "diskio.h"
uint32_t hw_read(unsigned o){return *(volatile uint32_t*)(MEDIA_BASE+o);}
void hw_write(unsigned o,uint32_t v){*(volatile uint32_t*)(MEDIA_BASE+o)=v;}
static unsigned char tx[2048],rx[2048];
int main(void){
 for(unsigned i=0;i<2048;i++)tx[i]=(i*37u+19)^0x5a;
 hw_write(HW_BOOT_STATUS,0xd9c00000);if(disk_initialize(0)){hw_write(HW_BOOT_STATUS,0xd9c0ee01);for(;;){}}
 hw_write(HW_BOOT_STATUS,0xd9c00001);unsigned w=disk_write(0,tx,8,4);hw_write(HW_BOOT_STATUS,0xd9c00002);
 unsigned r=disk_read(0,rx,8,4);hw_write(HW_BOOT_STATUS,0xd9c00003);
 if(w||r){hw_write(HW_BOOT_STATUS,0xd9c0ee02);for(;;){}}
 for(unsigned i=0;i<2048;i++)if(rx[i]!=tx[i]){hw_write(HW_BOOT_STATUS,0xd9c0ee03);for(;;){}}
 hw_write(HW_BOOT_STATUS,0xd9c0d00d);for(;;){}
}
