#include "CH56x_common.h"
#include "usb_device.h"
#include "msc_bot.h"
void link_init(void);void link_step(void);
int main(void){
    // 仅USB外设轮询，不启用WCH专有快速中断ABI；使用现有标准RISC-V GCC。
    SystemInit(80000000);R32_USB_CONTROL=0;link_init();msc_reset();
    for(;;){usb_step();if(msc_idle())link_step();}
}
