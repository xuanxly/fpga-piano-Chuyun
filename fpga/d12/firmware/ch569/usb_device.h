#ifndef PIANO_USB_DEVICE_H
#define PIANO_USB_DEVICE_H
void usb_enable(int);
void usb_poll(void); // 只处理总线/端点事件；可在GPIO等待期间调用，不递归处理SCSI。
void usb_step(void);
#endif
