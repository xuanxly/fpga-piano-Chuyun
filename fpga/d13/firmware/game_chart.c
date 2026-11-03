#include "game_chart.h"
#include <string.h>
void chart_reset(ChartParser*p){memset(p,0,sizeof(*p));}
static void space(const char**s){while(**s==' '||**s=='\t')++*s;}
static int number(const char**s,uint32_t*out,uint32_t max){
    space(s);uint32_t n=0;unsigned got=0;
    while(**s>='0'&&**s<='9'){unsigned d=*(*s)++-'0';if(n>(max-d)/10||d>max)return 0;n=n*10+d;got=1;}
    space(s);*out=n;return got;
}
int chart_line(ChartParser*p,const char*s,ChartEvent*e){
    space(&s);if(!*s||*s=='#')return 0;
    if(!p->header){if(strcmp(s,"PIANO28,1"))return -1;p->header=1;return 0;}
    if(!number(&s,&e->time,300000)||*s++!=','||!number(&s,&e->duration,60000)||*s++!=',')return -1;
    if(e->duration<40||e->time+e->duration>300000||p->notes>=4096||(p->notes&&e->time<=p->last))return -1;
    e->mask=0;
    for(;;){
        space(&s);unsigned k;switch(*s++){case 'C':k=0;break;case 'D':k=1;break;case 'E':k=2;break;case 'F':k=3;break;case 'G':k=4;break;case 'A':k=5;break;case 'B':k=6;break;default:return -1;}
        if(*s<'3'||*s>'6')return -1;k+=7*(*s++-'3');if(e->mask&(1u<<k))return -1;
        if(e->time<p->hold[k])return -1;e->mask|=1u<<k;space(&s);
        if(*s=='+'){s++;continue;}if(!*s||*s=='#')break;return -1;
    }
    for(unsigned i=0;i<28;i++)if(e->mask&(1u<<i))p->hold[i]=e->time+e->duration;
    p->last=e->time;if(e->time+e->duration>p->end)p->end=e->time+e->duration;p->notes++;
    return 1;
}
