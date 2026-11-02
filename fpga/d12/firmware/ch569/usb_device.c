/* CH569 USB2 register sequencing follows WCH MSC_U-Disk USB20 example (2023/02/16).
 * Copyright (c) 2021 Nanjing Qinheng Microelectronics. WCH MCU use only.
 * D12: polled events, real MSC requests, FS/HS descriptors, no EMMC or USB3 library.
 */
#include "CH56x_common.h"
#include "msc_bot.h"
#include "usb_device.h"
#include <stdint.h>
#include <string.h>
static uint8_t ep0[64] __attribute__((aligned(16),section(".DMADATA")));
static uint8_t ep_in[512] __attribute__((aligned(16),section(".DMADATA")));
static uint8_t ep_out[512] __attribute__((aligned(16),section(".DMADATA")));
static const uint8_t device[]={18,1,0,2,0,0,0,64,0x86,0x1a,0x10,0xfe,0x12,0,1,2,3,1};
static const uint8_t qualifier[]={10,6,0,2,0,0,0,64,1,0};
static const uint8_t language[]={4,3,9,4};
static const uint8_t manufacturer[]={16,3,'P',0,'I',0,'A',0,'N',0,'O',0,'2',0,'8',0};
static const uint8_t product[]={22,3,'P',0,'I',0,'A',0,'N',0,'O',0,' ',0,'D',0,'I',0,'S',0,'K',0};
static const uint8_t serial[]={18,3,'P',0,'I',0,'A',0,'N',0,'O',0,'0',0,'1',0,'2',0};
static uint8_t config[32]={9,2,32,0,1,1,0,0xc0,50,9,4,0,0,2,8,6,0x50,0,7,5,0x82,2,0,2,0,7,5,3,2,0,2,0};
static unsigned enabled,configured,bulk_busy,out_pending,out_size,control_left,pending_address,pending_set_address,control_in;
static const uint8_t*control_data;
static unsigned packet_size(void){return (R8_USB_SPD_TYPE&RB_USBSPEED_MASK)==UST_FS?64:512;}
static void endpoints(void){
    R8_UEP2_3_MOD=RB_UEP2_TX_EN|RB_UEP3_RX_EN;
    R16_UEP0_MAX_LEN=64;R16_UEP2_MAX_LEN=512;R16_UEP3_MAX_LEN=512;
    R32_UEP0_RT_DMA=(uint32_t)ep0;R32_UEP2_TX_DMA=(uint32_t)ep_in;R32_UEP3_RX_DMA=(uint32_t)ep_out;
    R16_UEP0_T_LEN=0;R8_UEP0_TX_CTRL=UEP_T_RES_NAK;R8_UEP0_RX_CTRL=UEP_R_RES_ACK;
    R16_UEP2_T_LEN=0;R8_UEP2_TX_CTRL=UEP_T_RES_NAK|RB_UEP_T_AUTOTOG;
    R8_UEP3_RX_CTRL=UEP_R_RES_ACK|RB_UEP_R_AUTOTOG;
    configured=bulk_busy=out_pending=control_left=pending_set_address=0;msc_reset();
}
void usb_enable(int on){
    if(!!on==enabled)return;enabled=!!on;
    if(on){R8_USB_CTRL=0;endpoints();R8_USB_INT_FG=0xff;R8_USB_INT_EN=0;
        R8_USB_CTRL=UCST_HS|RB_DEV_PU_EN|RB_USB_INT_BUSY|RB_USB_DMA_EN;}
    else{R8_USB_CTRL=RB_USB_CLR_ALL|RB_USB_RESET_SIE;configured=0;bulk_busy=out_pending=0;msc_reset();}
}
static void stall0(void){R16_UEP0_T_LEN=0;R8_UEP0_TX_CTRL=UEP_T_RES_STALL;R8_UEP0_RX_CTRL=UEP_R_RES_STALL;}
static void control_packet(void){
    unsigned n=control_left>64?64:control_left;
    if(n&&control_data!=ep0)memcpy(ep0,control_data,n);control_data+=n;control_left-=n;R16_UEP0_T_LEN=n;
}
static void setup(void){
    uint8_t req[8];memcpy(req,ep0,8);
    unsigned type=req[0],op=req[1],value=req[2]|req[3]<<8,index=req[4]|req[5]<<8,len=req[6]|req[7]<<8;
    const uint8_t*p=ep0;unsigned n=0,ok=1;control_left=0;control_in=!!(type&128);pending_set_address=0;
    if(type==0xa1&&op==0xfe&&value==0&&index==0&&len==1){ep0[0]=0;n=1;}
    else if(type==0x21&&op==0xff&&value==0&&index==0&&len==0){msc_reset();bulk_busy=out_pending=0;R8_UEP2_TX_CTRL=UEP_T_RES_NAK|RB_UEP_T_AUTOTOG;R8_UEP3_RX_CTRL=UEP_R_RES_ACK|RB_UEP_R_AUTOTOG;}
    else if((type&0x60)!=0)ok=0;
    else if(type==0x80&&op==6){
        switch(value>>8){
            case 1:p=device;n=sizeof(device);break;
            case 2:case 7:{unsigned m=packet_size();if((value>>8)==7)m=m==64?512:64;config[1]=value>>8;config[22]=config[29]=m&255;config[23]=config[30]=m>>8;p=config;n=sizeof(config);break;}
            case 6:p=qualifier;n=sizeof(qualifier);break;
            case 3:switch(value&255){case 0:p=language;n=sizeof(language);break;case 1:p=manufacturer;n=sizeof(manufacturer);break;case 2:p=product;n=sizeof(product);break;case 3:p=serial;n=sizeof(serial);break;default:ok=0;}break;
            default:ok=0;
        }
    }else if(type==0&&op==5&&value<128&&!len){pending_address=value;pending_set_address=1;}
    else if(type==0&&op==9&&value<=1&&!len){configured=value;msc_reset();}
    else if(type==0x80&&op==8){ep0[0]=configured;n=1;}
    else if(type==0x81&&op==10&&index==0){ep0[0]=0;n=1;}
    else if(type==1&&op==11&&value==0&&index==0&&!len){}
    else if(op==0&&(type==0x80||type==0x81||type==0x82)){
        ep0[0]=type==0x80?1:0;ep0[1]=0;n=2;
        if(type==0x82){if(index==0x82)ep0[0]=(R8_UEP2_TX_CTRL&RB_UEP_TRES_MASK)==UEP_T_RES_STALL;else if(index==3)ep0[0]=(R8_UEP3_RX_CTRL&RB_UEP_RRES_MASK)==UEP_R_RES_STALL;else if(index!=0&&index!=0x80)ok=0;}
    }else if(type==2&&(op==1||op==3)&&value==0&&!len){
        if(index==0x82){R8_UEP2_TX_CTRL=(op==3?UEP_T_RES_STALL:UEP_T_RES_NAK)|RB_UEP_T_AUTOTOG;if(op==1)msc_clear_halt(2);}
        else if(index==3){R8_UEP3_RX_CTRL=(op==3?UEP_R_RES_STALL:UEP_R_RES_ACK)|RB_UEP_R_AUTOTOG;if(op==1)msc_clear_halt(1);}else ok=0;
    }else ok=0;
    if(!ok){stall0();return;}
    control_data=p;control_left=n<len?n:len;control_packet();
    R8_UEP0_TX_CTRL=UEP_T_RES_ACK|RB_UEP_T_TOG_1;R8_UEP0_RX_CTRL=UEP_R_RES_ACK|RB_UEP_R_TOG_1;
}
void usb_poll(void){
    if(!enabled)return;unsigned flags=R8_USB_INT_FG;
    if(flags&RB_USB_IF_SETUOACT){setup();R8_USB_INT_FG=RB_USB_IF_SETUOACT;}
    else if(flags&RB_USB_IF_BUSRST){endpoints();R8_USB_DEV_AD=0;R8_USB_INT_FG=RB_USB_IF_BUSRST;}
    else if(flags&RB_USB_IF_TRANSFER){
        unsigned st=R8_USB_INT_ST,ep=st&15,pid=(st>>4)&3;
        if(ep==0){
            if(pid==2){if(pending_set_address){R8_USB_DEV_AD=pending_address;pending_set_address=0;}
                if(control_in&&control_left){control_packet();R8_UEP0_TX_CTRL^=RB_UEP_T_TOG_1;R8_UEP0_TX_CTRL=(R8_UEP0_TX_CTRL&~RB_UEP_TRES_MASK)|UEP_T_RES_ACK;}
                else{R8_UEP0_TX_CTRL=UEP_T_RES_NAK;R8_UEP0_RX_CTRL=UEP_R_RES_ACK|RB_UEP_R_TOG_1;}}
            else if(pid==0){R8_UEP0_TX_CTRL=UEP_T_RES_NAK;R8_UEP0_RX_CTRL=UEP_R_RES_ACK|RB_UEP_R_TOG_1;}
        }else if(ep==2&&pid==2){R8_UEP2_TX_CTRL=(R8_UEP2_TX_CTRL&~RB_UEP_TRES_MASK)|UEP_T_RES_NAK;bulk_busy=0;msc_tx_complete();}
        else if(ep==3&&pid==0&&(st&RB_USB_ST_TOGOK)){
            R8_UEP3_RX_CTRL=(R8_UEP3_RX_CTRL&~RB_UEP_RRES_MASK)|UEP_R_RES_NAK;out_size=R16_USB_RX_LEN;out_pending=1;
        }
        R8_USB_INT_FG=RB_USB_IF_TRANSFER;
    }else if(flags&RB_USB_IF_SUSPEND)R8_USB_INT_FG=RB_USB_IF_SUSPEND;
}
void usb_step(void){
    usb_poll();if(!enabled||!configured)return;
    if(out_pending){out_pending=0;msc_out(ep_out,out_size);if(!(msc_halted()&1))R8_UEP3_RX_CTRL=(R8_UEP3_RX_CTRL&~RB_UEP_RRES_MASK)|UEP_R_RES_ACK;}
    unsigned halt=msc_halted();
    if(halt&1)R8_UEP3_RX_CTRL=(R8_UEP3_RX_CTRL&~RB_UEP_RRES_MASK)|UEP_R_RES_STALL;
    if(halt&2)R8_UEP2_TX_CTRL=(R8_UEP2_TX_CTRL&~RB_UEP_TRES_MASK)|UEP_T_RES_STALL;
    if(!bulk_busy&&!(halt&2)){int n=msc_in(ep_in,packet_size());if(n>=0){R16_UEP2_T_LEN=n;R8_UEP2_TX_CTRL=(R8_UEP2_TX_CTRL&~RB_UEP_TRES_MASK)|UEP_T_RES_ACK;bulk_busy=1;}}
}
