#include "media_hw.h"
uint32_t hw_read(unsigned offset){return *(volatile uint32_t*)(uintptr_t)(MEDIA_BASE+offset);}
void hw_write(unsigned offset,uint32_t value){*(volatile uint32_t*)(uintptr_t)(MEDIA_BASE+offset)=value;}
int main(void){hw_write(HW_BOOT_STATUS,0xd9000001);media_init();for(;;)media_step();}
