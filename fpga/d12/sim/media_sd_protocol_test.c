#include "media_hw.h"
#include "ff.h"
#include "diskio.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
// Independent byte-level SDHC/SDXC card model. The driver under test is production sd_spi.c.
static unsigned cs=1,divider,rx=255,ms,clocks,cmd_at,head,tail,app_tries,read_multi,read_at,write_mode,write_at,write_index,bad_crc,reject_write,absent;
static unsigned char command_bytes[6],queue[2048],disk[64][512],block[514];static unsigned checks;
#define CHECK(x) do{checks++;if(!(x)){fprintf(stderr,"FAIL %d %s\n",__LINE__,#x);exit(1);}}while(0)
static unsigned crc16(const unsigned char*p,unsigned n){unsigned c=0;while(n--){c^=*p++<<8;for(unsigned i=0;i<8;i++)c=((c<<1)^((c&0x8000)?0x1021:0))&65535;}return c;}
static unsigned crc7(const unsigned char*p,unsigned n){unsigned c=0;while(n--){unsigned b=*p++;for(unsigned i=0;i<8;i++){c<<=1;if((b^c)&128)c^=9;b<<=1;}}return(c<<1|1)&255;}
static void push(unsigned v){queue[tail++%2048]=v;}
static void data(const unsigned char*p,unsigned n){unsigned c=crc16(p,n);push(255);push(254);for(unsigned i=0;i<n;i++)push(p[i]);push(c>>8);push(c^(bad_crc?1:0));}
static void cmd(void){unsigned c=command_bytes[0]&63;uint32_t a=(uint32_t)command_bytes[1]<<24|(uint32_t)command_bytes[2]<<16|command_bytes[3]<<8|command_bytes[4];CHECK(command_bytes[5]==crc7(command_bytes,5));
 switch(c){case 0:CHECK(clocks>=80&&divider>=63);push(1);break;case 8:CHECK(a==0x1aa);push(1);push(0);push(0);push(1);push(0xaa);break;case 55:push(app_tries?0:1);break;case 41:CHECK(a==0x40000000);push(app_tries++?0:1);break;case 58:push(0);push(0xc0);push(0xff);push(0x80);push(0);break;
 case 9:{unsigned char csd[16]={0x40};csd[7]=3;csd[8]=255;csd[9]=255;push(0);data(csd,16);break;}
 case 17:case 18:CHECK(divider==2&&a<64);push(0);read_at=a;data(disk[read_at++],512);read_multi=c==18;break;
 case 12:push(255);push(0);read_multi=0;break;
 case 24:case 25:CHECK(divider==2&&a<64);push(0);write_mode=c==25?2:1;write_at=a;write_index=0;break;
 default:fprintf(stderr,"unexpected CMD%u\n",c);exit(1);
 }
}
static unsigned exchange(unsigned v){if(cs||absent){clocks+=8;return 255;}if(head<tail)return queue[head++%2048];
 if(write_mode){if(write_index){block[write_index++-1]=v;if(write_index==515){unsigned c=crc16(block,512);CHECK(block[512]==(c>>8)&&block[513]==(c&255));if(!reject_write)memcpy(disk[write_at++],block,512);push(reject_write?11:5);push(0);push(255);write_index=0;if(write_mode==1)write_mode=0;}return 255;}
  if(v==253){CHECK(write_mode==2);write_mode=0;return 255;}if(v==254||v==252){CHECK((write_mode==1&&v==254)||(write_mode==2&&v==252));write_index=1;}return 255;}
 if(cmd_at||((v&0xc0)==0x40)){command_bytes[cmd_at++]=v;if(cmd_at==6){cmd_at=0;cmd();}return 255;}
 if(read_multi){data(disk[read_at++],512);return queue[head++%2048];}return 255;
}
uint32_t hw_read(unsigned off){if(off==HW_MS)return ms++;if(off==HW_SPI_RX)return rx<<8;return 0;}
void hw_write(unsigned off,uint32_t v){if(off==HW_SPI_CFG){unsigned old=cs;cs=v>>16&1;divider=v&65535;if(cs&&!old){head=tail=cmd_at=read_multi=write_mode=0;}}else if(off==HW_SPI_TX)rx=exchange(v&255);}
int main(void){unsigned char out[1536],in[1536];for(unsigned i=0;i<1536;i++)out[i]=(i*37+19)^0x5a;
 CHECK(disk_initialize(0)==0);LBA_t sectors;CHECK(disk_ioctl(0,GET_SECTOR_COUNT,&sectors)==RES_OK&&sectors==268435456);
 CHECK(disk_write(0,out,4,1)==RES_OK);CHECK(disk_read(0,in,4,1)==RES_OK&&!memcmp(in,out,512));
 CHECK(disk_write(0,out,8,3)==RES_OK);CHECK(disk_read(0,in,8,3)==RES_OK&&!memcmp(in,out,1536));
 CHECK(disk_read(0,in,sectors,1)==RES_PARERR);CHECK(disk_ioctl(0,CTRL_SYNC,0)==RES_OK);
 bad_crc=1;CHECK(disk_read(0,in,4,1)==RES_ERROR&&disk_status(0)==STA_NOINIT);bad_crc=0;CHECK(disk_initialize(0)==0);
 reject_write=1;CHECK(disk_write(0,out,4,1)==RES_ERROR);reject_write=0;CHECK(disk_initialize(0)==0);
 absent=1;CHECK(disk_read(0,in,4,1)==RES_ERROR);CHECK(disk_initialize(0)==STA_NOINIT);
 printf("PASS media_sd_protocol: %u checks; CRC7 commands, CRC16 payloads, init/run clock, SDXC CSD, CMD17/18/12/24/25, bounded absent/CRC/reject handling\n",checks);return 0;}
