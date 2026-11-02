#include "mp3dec.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char**argv){
 if(argc!=3)return 2;FILE*f=fopen(argv[1],"rb"),*o=fopen(argv[2],"wb");if(!f||!o)return 3;
 fseek(f,0,SEEK_END);int n=ftell(f);rewind(f);unsigned char*b=malloc(n),*p=b;if(!b||fread(b,1,n,f)!=(unsigned)n)return 4;fclose(f);
 HMP3Decoder d=MP3InitDecoder();short pcm[2304];unsigned frames=0;MP3FrameInfo info={0};
 while(n>=4){int skip=MP3FindSyncWord(p,n);if(skip<0)break;p+=skip;n-=skip;unsigned char*start=p;
  int result=MP3Decode(d,&p,&n,pcm,0);if(p==start){p++;n--;}
  if(result==0){MP3GetLastFrameInfo(d,&info);if(fwrite(pcm,2,info.outputSamps,o)!=(unsigned)info.outputSamps)return 5;frames++;}
 }
 fclose(o);MP3FreeDecoder(d);free(b);printf("%u %d %d\n",frames,info.samprate,info.nChans);return frames?0:6;
}
