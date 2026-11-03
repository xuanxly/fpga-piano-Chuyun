#ifndef PIANO_MSC_BOT_H
#define PIANO_MSC_BOT_H
#include <stdint.h>
// 传输层只在完整OUT包到达/IN空闲时调用；底层SD服务返回前不会向主机确认写入成功。
void msc_reset(void);
void msc_out(const uint8_t*,unsigned);
int msc_in(uint8_t*,unsigned); // -1=NAK；0也可能是合法ZLP
void msc_tx_complete(void);
int msc_idle(void);
int msc_halted(void);
void msc_clear_halt(unsigned);
uint32_t disk_blocks(void);
int block_read(uint32_t,uint8_t*);
int block_write(uint32_t,const uint8_t*);
int block_sync(void);
void disk_eject(void);
#endif
