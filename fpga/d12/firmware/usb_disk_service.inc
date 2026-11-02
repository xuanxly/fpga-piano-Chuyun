// CH569专用块设备协议。任何READ/WRITE前必须完成身份握手且FatFs已卸载。
static unsigned usb_authenticated,usb_closing;
static uint32_t usb_last_byte;static unsigned usb_rx_at,usb_need,usb_tx_at,usb_tx_size;
static uint8_t usb_packet[530],usb_reply[530];
static uint16_t link_crc(const uint8_t*p,unsigned n){uint16_t c=0xffff;while(n--){c^=(uint16_t)*p++<<8;for(unsigned i=0;i<8;i++)c=(c<<1)^((c&0x8000)?0x1021:0);}return c;}
static void usb_response(unsigned op,unsigned seq,unsigned n){
    usb_reply[0]=0xd5;usb_reply[1]=0x12;usb_reply[2]=op|0x80;usb_reply[3]=seq;put16(usb_reply+4,n);
    put16(usb_reply+6+n,link_crc(usb_reply,6+n));usb_tx_at=0;usb_tx_size=n+8;
}
static void usb_finish_export(void){
    if(!usb_exported)return;
    if(disk_ioctl(0,CTRL_SYNC,0)!=RES_OK){usb_exported=usb_closing=0;mounted=0;error(MSG_IO_ERROR);return;}
    usb_exported=usb_closing=0;mounted=0;message=MSG_READY;next_mount=hw_read(HW_MS)+100;
}
static void usb_disk_toggle(void){
    if(usb_exported){usb_closing=1;message=MSG_USB_UNPLUG;publish();return;}
    if(!usb_authenticated){error(MSG_USB_WAIT);return;}
    if(rec_state==REC_RUNNING||rec_state==REC_PAUSED)finish_record(MSG_SAVED);
    if(rec_state==REC_ERROR||!mounted){error(MSG_NO_CARD);return;}
    stop_play();game_stop();
    if(disk_ioctl(0,CTRL_SYNC,0)!=RES_OK){error(MSG_IO_ERROR);return;}
    static const TCHAR empty[]={0};f_mount(0,empty,0);mounted=0;
    usb_exported=1;usb_closing=0;message=MSG_USB_EXPORTED;entry_count=0;publish();
}
static void usb_request(void){
    unsigned op=usb_packet[2],seq=usb_packet[3],n=le16(usb_packet+4);uint8_t*p=usb_packet+6;
    if(op==1&&n==8&&!memcmp(p,"PIANO12!",8)){
        // HELLO是唯一允许使能FPGA输出的入口；原厂HSPI固件不会产生此包。
        usb_authenticated=1;hw_write(HW_USB_CTL,1);usb_reply[6]=1;usb_response(op,seq,1);return;
    }
    if(!usb_authenticated)return;
    usb_reply[6]=0;
    if(op==2&&n==0){LBA_t sectors=0;if(usb_exported)disk_ioctl(0,GET_SECTOR_COUNT,&sectors);usb_reply[6]=usb_closing?2:usb_exported?1:0;put32(usb_reply+7,(uint32_t)sectors);usb_response(op,seq,5);return;}
    if(op==6&&n==0){usb_finish_export();usb_response(op,seq,1);return;}
    if(!usb_exported){usb_reply[6]=1;usb_response(op,seq,1);return;}
    if(op==3&&n==4){DRESULT r=disk_read(0,usb_reply+7,le32(p),1);usb_reply[6]=r!=RES_OK;usb_response(op,seq,r==RES_OK?513:1);}
    else if(op==4&&n==516){usb_reply[6]=disk_write(0,p+4,le32(p),1)!=RES_OK;usb_response(op,seq,1);}
    else if(op==5&&n==0){usb_reply[6]=disk_ioctl(0,CTRL_SYNC,0)!=RES_OK;usb_response(op,seq,1);}
    else {usb_reply[6]=1;usb_response(op,seq,1);}
}
static void usb_service(void){
    unsigned flags=hw_read(HW_USB_STATUS);
    if(!(flags&1)){
        if(usb_exported)usb_finish_export();usb_authenticated=0;usb_rx_at=usb_need=usb_tx_at=usb_tx_size=0;hw_write(HW_USB_CTL,0);return;
    }
    if(usb_tx_at<usb_tx_size){
        unsigned free=hw_read(HW_USB_TX_FREE);while(free--&&usb_tx_at<usb_tx_size)hw_write(HW_USB_TX,usb_reply[usb_tx_at++]);
        return; // 请求/响应串行，回复尚未入队时禁止覆盖缓冲。
    }
    unsigned available=hw_read(HW_USB_RX_COUNT);
    while(available--){
        unsigned b=hw_read(HW_USB_RX)&255;usb_last_byte=hw_read(HW_MS);
        if(usb_rx_at==0&&b!=0xd5)continue;
        if(usb_rx_at==1&&b!=0x12){usb_rx_at=b==0xd5?1:0;continue;}
        usb_packet[usb_rx_at++]=(uint8_t)b;
        if(usb_rx_at==6){unsigned n=le16(usb_packet+4);if(n>516){usb_rx_at=0;continue;}usb_need=n+8;}
        if(usb_rx_at>=8&&usb_rx_at==usb_need){
            if(link_crc(usb_packet,usb_need-2)==le16(usb_packet+usb_need-2))usb_request();
            usb_rx_at=usb_need=0;if(usb_tx_at<usb_tx_size)break;
        }
    }
    if(usb_rx_at&&hw_read(HW_MS)-usb_last_byte>2000)usb_rx_at=usb_need=0;
}
