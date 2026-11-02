// 包含在媒体服务中，复用单一FIL和目录列表；游戏与录音/播放不会同时占卡。
static ChartParser chart;

static const TCHAR songs_dir[]={'/','S','O','N','G','S',0};
static int chart_readline(char*line,unsigned cap){
    unsigned n=0;UINT got;unsigned char c;
    for(;;){if(f_read(&stream,&c,1,&got)!=FR_OK)return -1;if(!got){if(!n)return 0;break;}
        if(c=='\n')break;if(c=='\r')continue;if(c<32&&c!='\t')return -1;
        if(n+1>=cap)return -1;line[n++]=(char)c;}
    while(n&&(line[n-1]==' '||line[n-1]=='\t'))n--;line[n]=0;return 1;
}
static void game_stop(void){
    hw_write(HW_GAME_CTL,4|(game_practice?8:0));
    if(game_stream&&stream_open){f_close(&stream);stream_open=0;}game_stream=0;
}
static void game_feed(void){
    char line[128];ChartEvent e;
    while(game_stream&&((hw_read(HW_GAME_CTL)>>16)&63)){
        int r=chart_readline(line,sizeof(line));
        if(r==0){
            hw_write(HW_GAME_TIME,chart.end+1);hw_write(HW_GAME_MASK,0x80000000u);hw_write(HW_GAME_DURATION,0);hw_write(HW_GAME_COMMIT,1);
            f_close(&stream);stream_open=0;game_stream=0;return;
        }
        if(r<0||(r=chart_line(&chart,line,&e))<0){game_stop();error(MSG_BAD_CHART);return;}
        if(r){hw_write(HW_GAME_TIME,e.time);hw_write(HW_GAME_MASK,e.mask);hw_write(HW_GAME_DURATION,e.duration);hw_write(HW_GAME_COMMIT,1);}
    }
}
static void game_open(unsigned row){
    if(!mounted||row>=entry_count||!suffix(names[row],"csv"))return;
    if(rec_state==REC_RUNNING||rec_state==REC_PAUSED)finish_record(MSG_SAVED);
    if(rec_state==REC_ERROR)return;
    stop_play();game_stop();TCHAR path[272];unsigned n=tlen(songs_dir);
    tcopy(path,songs_dir);path[n++]='/';tcopy(path+n,names[row]);
    if(f_open(&stream,path,FA_READ)!=FR_OK){error(MSG_IO_ERROR);return;}
    stream_open=game_stream=1;message=MSG_LOADING;publish();chart_reset(&chart);
    // 先完整校验再演奏，拒绝重复键/倒序/超时/截断谱面；不把几分钟谱面整份放入RAM。
    char line[128];ChartEvent e;int r;
    if(f_size(&stream)>262144){game_stop();error(MSG_BAD_CHART);return;}
    while((r=chart_readline(line,sizeof(line)))>0){if(chart_line(&chart,line,&e)<0){r=-1;break;}}
    if(r<0||!chart.header||!chart.notes||f_lseek(&stream,0)!=FR_OK){game_stop();error(MSG_BAD_CHART);return;}
    if(hw_read(HW_PAGE)!=PAGE_GAME){game_stop();return;}
    chart_reset(&chart);text_row(7,names[row]);game_feed();
    if(message==MSG_BAD_CHART)return;
    hw_write(HW_GAME_CTL,1|(game_practice?8:0));message=MSG_READY;publish();
}
