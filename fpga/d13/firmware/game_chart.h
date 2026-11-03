#ifndef GAME_CHART_H
#define GAME_CHART_H
#include <stdint.h>
// 无动态分配的CSV校验状态；同一键不得在旧长音结束之前再次触发。
typedef struct {uint32_t last,end,hold[28],notes;unsigned header;} ChartParser;
typedef struct {uint32_t time,mask,duration;} ChartEvent;
void chart_reset(ChartParser*);
int chart_line(ChartParser*,const char*,ChartEvent*); // 1事件，0空行/标题，-1无效
#endif
