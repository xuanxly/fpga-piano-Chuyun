#include <stddef.h>
#include <stdint.h>
// D12不含MP3解码；保留小型兼容堆，文件名使用FatFs静态缓冲。
static unsigned char heap[1024] __attribute__((aligned(8)));
static size_t heap_at;
void media_heap_reset(void){heap_at=0;}
size_t media_heap_used(void){return heap_at;}
void *malloc(size_t n){n=(n+7)&~(size_t)7;if(n>sizeof(heap)-heap_at)return 0;void*p=heap+heap_at;heap_at+=n;return p;}
void free(void*p){(void)p;}
__attribute__((used,externally_visible)) void *memset(void*d,int v,size_t n){unsigned char*p=d;while(n--)*p++=(unsigned char)v;return d;}
__attribute__((used,externally_visible)) void *memcpy(void*d,const void*s,size_t n){unsigned char*p=d;const unsigned char*q=s;while(n--)*p++=*q++;return d;}
__attribute__((used,externally_visible)) void *memmove(void*d,const void*s,size_t n){unsigned char*p=d;const unsigned char*q=s;if(p<q){while(n--)*p++=*q++;}else{p+=n;q+=n;while(n--)*--p=*--q;}return d;}
int memcmp(const void*a,const void*b,size_t n){const unsigned char*p=a,*q=b;while(n--){if(*p!=*q)return *p-*q;p++;q++;}return 0;}
size_t strlen(const char*s){size_t n=0;while(s[n])n++;return n;}
int strcmp(const char*a,const char*b){while(*a&&*a==*b){a++;b++;}return (unsigned char)*a-(unsigned char)*b;}
char *strchr(const char*s,int c){do{if(*s==(char)c)return(char*)s;}while(*s++);return 0;}
char *strrchr(const char*s,int c){char*p=0;do{if(*s==(char)c)p=(char*)s;}while(*s++);return p;}
