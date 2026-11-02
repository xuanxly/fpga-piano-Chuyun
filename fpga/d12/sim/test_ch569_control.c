#include <assert.h>
#include <stdio.h>
#include "../firmware/ch569/usb_device.c"
uint32_t disk_blocks(void){return 250000000;}
int block_read(uint32_t lba,uint8_t*p){(void)lba;memset(p,0x5a,512);return 1;}
int block_write(uint32_t lba,const uint8_t*p){(void)lba;(void)p;return 1;}
int block_sync(void){return 1;}void disk_eject(void){}
static void request(unsigned type,unsigned op,unsigned value,unsigned index,unsigned len){
    ep0[0]=type;ep0[1]=op;ep0[2]=value;ep0[3]=value>>8;ep0[4]=index;ep0[5]=index>>8;ep0[6]=len;ep0[7]=len>>8;
    mock_USB_INT_FG=RB_USB_IF_SETUOACT;usb_poll();mock_USB_INT_FG=0;
}
static void complete(unsigned ep,unsigned pid){mock_USB_INT_ST=ep|(pid<<4)|RB_USB_ST_TOGOK;mock_USB_INT_FG=RB_USB_IF_TRANSFER;usb_poll();mock_USB_INT_FG=0;}
int main(void){
    usb_enable(1);assert(enabled&&!configured);
    request(0x80,6,0x100,0,64);assert(mock_UEP0_T_LEN==18&&ep0[0]==18&&ep0[7]==64);
    request(0x80,6,0x200,0,255);assert(mock_UEP0_T_LEN==32&&ep0[14]==8&&ep0[16]==0x50&&ep0[20]==0x82&&ep0[27]==3);
    mock_USB_SPD_TYPE=UST_FS;request(0x80,6,0x200,0,255);assert(ep0[22]==64&&ep0[23]==0&&ep0[29]==64);
    request(0x80,6,0x700,0,255);assert(ep0[1]==7&&ep0[22]==0&&ep0[23]==2);
    request(0x80,6,0x300,0,255);assert(ep0[0]==4);request(0x80,6,0x301,0x409,255);assert(ep0[0]==16);
    request(0x80,6,0x302,0x409,255);assert(ep0[0]==22);request(0x80,6,0x303,0x409,255);assert(ep0[0]==18);
    request(0x80,6,0x600,0,10);assert(ep0[1]==6&&mock_UEP0_T_LEN==10);
    request(0,5,7,0,0);assert(mock_USB_DEV_AD==0);complete(0,2);assert(mock_USB_DEV_AD==7);
    request(0,9,1,0,0);assert(configured==1);request(0x80,8,0,0,1);assert(ep0[0]==1);
    request(0xa1,0xfe,0,0,1);assert(ep0[0]==0&&mock_UEP0_T_LEN==1);
    request(0x21,0xff,0,0,0);assert(msc_idle());
    request(0x21,0xfe,0,0,1);assert((mock_UEP0_TX_CTRL&RB_UEP_TRES_MASK)==UEP_T_RES_STALL);
    request(0x80,6,0xff00,0,1);assert((mock_UEP0_TX_CTRL&RB_UEP_TRES_MASK)==UEP_T_RES_STALL);
    request(2,3,0,0x82,0);assert((mock_UEP2_TX_CTRL&RB_UEP_TRES_MASK)==UEP_T_RES_STALL);
    request(2,1,0,0x82,0);assert((mock_UEP2_TX_CTRL&RB_UEP_TRES_MASK)==UEP_T_RES_NAK);
    request(2,3,0,3,0);assert((mock_UEP3_RX_CTRL&RB_UEP_RRES_MASK)==UEP_R_RES_STALL);
    request(2,1,0,3,0);assert((mock_UEP3_RX_CTRL&RB_UEP_RRES_MASK)==UEP_R_RES_ACK);
    mock_USB_INT_FG=RB_USB_IF_BUSRST;usb_poll();mock_USB_INT_FG=0;assert(!configured&&mock_USB_DEV_AD==0&&msc_idle());
    usb_enable(0);assert(!enabled);
    puts("PASS CH569 target EP0 code: device/config/FS-HS/qualifier/strings,address delayed,configuration,MSC reset/maxLUN,stall,clearhalt,busreset,disconnect");
}
