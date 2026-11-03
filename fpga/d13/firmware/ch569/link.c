#include "CH56x_common.h"
#include "msc_bot.h"
#include "usb_device.h"
#include <stdint.h>
#include <string.h>
// NEO31005第21页：HD0..3=PA5/4/22/3，HD4=PA2。
// TX改用HD5/6/7/12=PA1/PA0/PB21/PA17，RX_REQ用HD13=PB16。
// 避开FPGA的专用I2C/SSPI脚，不改变启动配置；HTREQ=PA9，HTCLK=PA11，HTVLD=PA21。
#define READY (1u<<2)
#define RX_REQ (1u<<16) // PB16/HD13
#define TX_ACK (1u<<21)
#define RX_ACK (1u<<9)
#define TX_REQ (1u<<11)
#define NIBBLE ((1u<<5)|(1u<<4)|(1u<<22)|(1u<<3))
static unsigned rx_toggle,tx_seen,authenticated,active,seq,ejected;
static uint32_t sectors,last_poll;
static uint8_t packet[524],reply[524];
uint32_t cycles(void){uint32_t n;__asm__ volatile("csrr %0,0xb00":"=r"(n));return n;}
static uint16_t crc16(const uint8_t*p,unsigned n){uint16_t c=0xffff;while(n--){c^=(uint16_t)*p++<<8;for(unsigned i=0;i<8;i++)c=(c<<1)^((c&0x8000)?0x1021:0);}return c;}
static uint32_t le32(const uint8_t*p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put32(uint8_t*p,uint32_t n){for(unsigned i=0;i<4;i++){p[i]=n;n>>=8;}}
static int send_nibble(unsigned b){
    uint32_t bits=((b&1)<<5)|((b&2)<<3)|((b&4)<<20)|((b&8));
    R32_PA_OUT=(R32_PA_OUT&~NIBBLE)|bits;
    __asm__ volatile("fence iorw,iorw":::"memory");
    rx_toggle^=1;if(rx_toggle)R32_PB_OUT|=RX_REQ;else R32_PB_CLR=RX_REQ;
    uint32_t start=cycles();
    while(!!(R32_PA_PIN&RX_ACK)!=rx_toggle){usb_poll();if(cycles()-start>160000000u)return 0;}
    return 1;
}
static int send_byte(unsigned b){return send_nibble(b&15)&&send_nibble(b>>4);}
static int receive_nibble(unsigned*b){
    uint32_t start=cycles();
    while(!!(R32_PA_PIN&TX_REQ)==tx_seen){usb_poll();if(cycles()-start>160000000u)return 0;}
    // FPGA数据早于REQ稳定；MCU读取后才ACK，支持任意端的短暂停顿。
    uint32_t a=R32_PA_PIN,p=R32_PB_PIN;*b=((a>>1)&1)|((a<<1)&2)|((p>>19)&4)|((a>>14)&8);
    tx_seen^=1;if(tx_seen)R32_PA_OUT|=TX_ACK;else R32_PA_CLR=TX_ACK;return 1;
}
static int receive_byte(unsigned*b){unsigned a,c;if(!receive_nibble(&a)||!receive_nibble(&c))return 0;*b=a|(c<<4);return 1;}
static int rpc(unsigned op,const uint8_t*p,unsigned n,unsigned*length){
    unsigned serial=++seq&255;packet[0]=0xd5;packet[1]=0x12;packet[2]=op;packet[3]=serial;packet[4]=n;packet[5]=n>>8;
    if(n)memcpy(packet+6,p,n);uint16_t c=crc16(packet,n+6);packet[n+6]=c;packet[n+7]=c>>8;
    for(unsigned i=0;i<n+8;i++)if(!send_byte(packet[i]))return 0;
    unsigned at=0,need=0,b;
    while(at<sizeof(reply)){
        if(!receive_byte(&b))return 0;
        if(!at&&b!=0xd5)continue;if(at==1&&b!=0x12){at=b==0xd5?1:0;continue;}
        reply[at++]=b;if(at==6){need=reply[4]|reply[5]<<8;if(need>516)return 0;need+=8;}
        if(need&&at==need){if(reply[2]!=(op|128)||reply[3]!=serial||crc16(reply,need-2)!=(reply[need-2]|reply[need-1]<<8))return 0;*length=need-8;return 1;}
    }return 0;
}
static void link_reset(void){
    usb_enable(0);R32_PA_CLR=READY;authenticated=active=ejected=0;sectors=0;
    // READY低使FPGA清空双向FIFO和身份锁；重新从0相位握手，禁止盲目重试WRITE。
    uint32_t start=cycles();while(cycles()-start<800000u){}
    R32_PB_CLR=RX_REQ;R32_PA_CLR=TX_ACK|NIBBLE;rx_toggle=tx_seen=0;R32_PA_OUT|=READY;
}
void link_init(void){
    R8_HSPI_CTRL=0;R8_HSPI_CFG=0;
    R32_PA_CLR=READY|TX_ACK|NIBBLE;R32_PB_CLR=RX_REQ;
    R32_PA_DIR&=~(RX_ACK|TX_REQ|(1u<<1)|(1u<<0)|(1u<<17));R32_PB_DIR&=~(1u<<21);
    R32_PA_DIR|=READY|TX_ACK|NIBBLE;R32_PB_DIR|=RX_REQ;link_reset();last_poll=cycles();
}
void link_step(void){
    if(cycles()-last_poll<8000000u)return;last_poll=cycles();unsigned n;
    if(ejected){usb_enable(0);ejected=0;if(!rpc(6,0,0,&n)){link_reset();return;}}
    if(!authenticated){if(rpc(1,(const uint8_t*)"PIANO12!",8,&n)&&n==1&&reply[6]==1)authenticated=1;else{link_reset();return;}}
    if(!rpc(2,0,0,&n)||n!=5){link_reset();return;}
    unsigned state=reply[6];sectors=le32(reply+7);
    if(state==2){
        // EJECT先断开USB控制器，再同步卡，最后交还FPGA；不会让双方同时访问文件系统。
        usb_enable(0);active=0;
        if(!rpc(5,0,0,&n)||n!=1||reply[6]||!rpc(6,0,0,&n)){link_reset();return;}
        sectors=0;return;
    }
    if(state==1&&sectors){active=1;usb_enable(1);}else{active=0;usb_enable(0);}
}
uint32_t disk_blocks(void){return active?sectors:0;}
int block_read(uint32_t lba,uint8_t*out){
    uint8_t arg[4];put32(arg,lba);unsigned n;
    if(!active||lba>=sectors)return 0;
    if(!rpc(3,arg,4,&n)){link_reset();return 0;}if(n!=513||reply[6])return 0;
    memcpy(out,reply+7,512);return 1;
}
int block_write(uint32_t lba,const uint8_t*in){
    uint8_t arg[516];put32(arg,lba);memcpy(arg+4,in,512);unsigned n;
    // 不重试未知结果的WRITE；CRC错误/超时交由主机报告失败并重新挂载。
    if(!active||lba>=sectors)return 0;if(!rpc(4,arg,sizeof(arg),&n)){link_reset();return 0;}return n==1&&!reply[6];
}
int block_sync(void){unsigned n;if(!active)return 0;if(!rpc(5,0,0,&n)){link_reset();return 0;}return n==1&&!reply[6];}
void disk_eject(void){
    // 主机已停止使用介质。延迟USB断开到当前CSW发出之后，由主循环完成。
    active=0;sectors=0;ejected=1;
}
