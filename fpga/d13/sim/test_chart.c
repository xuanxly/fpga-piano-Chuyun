#include "game_chart.h"
#include <assert.h>
#include <stdio.h>
int main(void){
    ChartParser p;ChartEvent e;chart_reset(&p);
    assert(chart_line(&p,"# comment",&e)==0);assert(chart_line(&p,"PIANO28,1",&e)==0);
    assert(chart_line(&p,"0,500,C3+E3+G3",&e)==1&&e.mask==21);
    assert(chart_line(&p,"500,40,B6",&e)==1&&e.mask==(1u<<27));
    const char*bad[]={"500,40,C3","600,0,C3","600,40,C#3","600,40,C2","600,40,C7","600,40,C3+C3","600,40,","600,40,C3+","999999999999,40,C3","299999,40,C3","a,40,C3"};
    for(unsigned i=0;i<sizeof(bad)/sizeof(*bad);i++){ChartParser q=p;assert(chart_line(&q,bad[i],&e)<0);}
    assert(chart_line(&p,"1000,800,C3+E3",&e)==1);assert(chart_line(&p,"1200,100,C3",&e)<0);
    puts("PASS chart validation: notes chords octave range overlaps duplicates duration bounds malformed input");
}
