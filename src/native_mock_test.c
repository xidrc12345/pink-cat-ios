typedef unsigned int uint32_t;typedef int int32_t;typedef unsigned long long size_t;
#define va_list __builtin_va_list
#define va_start __builtin_va_start
#define va_arg __builtin_va_arg
#define va_end __builtin_va_end
typedef uint32_t u32;typedef int32_t i32;typedef unsigned long long u64;typedef size_t usize;
#define A32(p) __atomic_load_n((p),__ATOMIC_ACQUIRE)
#define A64(p) A32(p)
#define W32(p,v) __atomic_store_n((p),(v),__ATOMIC_RELEASE)
#define W64(p,v) W32(p,v)
static struct {u32 publishing;} PinkCatAudioState={1};
u32 mach_task_self_=1;
int mach_vm_read_overwrite(u32 t,u64 a,u64 n,u64 o,u64 *got){(void)t;for(size_t j=0;j<n;j++)((unsigned char*)o)[j]=((unsigned char*)a)[j];*got=n;return 0;}
int mach_vm_region(u32 t,u64 *a,u64 *n,int f,int *i,u32 *c,u32 *o){(void)t;(void)a;(void)n;(void)f;(void)i;(void)c;(void)o;return 1;}
int mach_port_deallocate(u32 t,u32 p){(void)t;(void)p;return 0;}
u32 _dyld_image_count(void){return 0;}
const char *_dyld_get_image_name(u32 i){(void)i;return 0;}
const void *_dyld_get_image_header(u32 i){(void)i;return 0;}
static char *strstr(const char*a,const char*b){(void)a;(void)b;return 0;}
#include "AudioPolicy.h"
#include "NativeCodec.h"
static int calls,flag,ctlCalls,failCtl;static void *seenFrame;
static void Original(void *self,void *frame,int v){(void)self;calls++;flag=v;seenFrame=frame;}
static int Ctl(void *s,int request,...){
    va_list ap;va_start(ap,request);int v=va_arg(ap,int);va_end(ap);ctlCalls++;
    if(failCtl&&request==4006){failCtl=0;return -1;}
    int *p=s;
    switch(request){case 4006:p[0x94/4]=v;p[0x3c/4]=1-v;break;case 4020:p[0x98/4]=v;break;case 4016:p[0xb8/4]=v;break;default:return -5;}
    return 0;
}
static int checks;__declspec(dllexport) const char *failedExpression=0;
#define CHECK(x) do{checks++;if(!(x)){failedExpression=#x;return -__LINE__;}}while(0)
static void put(void *p,int at,int value){*(i32*)((char*)p+at)=value;}
__declspec(dllexport) int run_tests(void){
    for(int r=-1;r<1000;r++){CHECK(PCRateAllowed(r)==(r==0||r==192));CHECK(PCNativeRateValid(r,1)==(r==192));CHECK(PCNativeRateValid(r,2)==(r==192));}
    CHECK(PCNativeMayApply(192,192000,192000));CHECK(!PCNativeMayApply(192,128000,128000));CHECK(!PCNativeMayApply(192,192000,48000));
    static unsigned char e[0xfa0],s[0x4000],src[0x1a28];
    *(u64*)(e+0x10)=(u64)s;*(u64*)(e+0x58)=(u64)src;*(u64*)(src+0x158)=(u64)e;
    put(e,0x18,48000);put(e,0x1c,1);put(e,0x20,960);put(e,0xf9c,1920);put(s,0x70,1);put(s,0x6c,2049);put(s,0xa4,192000);put(s,0x94,1);put(s,0x98,0);put(s,0xb8,1);put(src,0x198,192000);
    nativeBase=(u64)Ctl-0xa2df54;nativeOldEncode=Original;NativeArm(192,0);W64(&nativeMain,(u64)src);
    void *frame=(void*)0x1234;NativeEncode(e,frame,1);
    CHECK(calls==1&&flag==0&&seenFrame==frame);CHECK(ctlCalls==3);CHECK(PinkCatNativeState.appliedBps==192000);CHECK(*(i32*)(s+0x94)==0&&*(i32*)(s+0x3c)==1&&*(i32*)(s+0xb8)==0);
    NativeEncode(e,frame,1);CHECK(calls==2&&ctlCalls==3);
    put(s,0xa4,128000);NativeEncode(e,frame,1);CHECK(flag==1&&ctlCalls==3&&PinkCatNativeState.appliedBps==0);put(s,0xa4,192000);
    put(e,0x18,44100);NativeEncode(e,frame,1);CHECK(flag==1&&ctlCalls==3);put(e,0x18,48000);
    W64(&nativeMain,0);NativeEncode(e,frame,1);CHECK(flag==1&&ctlCalls==3);W64(&nativeMain,(u64)src);
    NativeArm(0,0);NativeEncode(e,frame,1);CHECK(flag==1&&*(i32*)(s+0x94)==1&&*(i32*)(s+0xb8)==1&&*(i32*)(s+0x98)==0);
    NativeArm(192,0);W64(&nativeMain,(u64)src);failCtl=1;NativeEncode(e,frame,1);CHECK(flag==1&&PinkCatNativeState.error==413&&*(i32*)(s+0x94)==1&&*(i32*)(s+0xb8)==1);
    CHECK(PCNativeShapeValid(48000,1,1,960,1920,2049));CHECK(!PCNativeShapeValid(48000,1,1,960,3840,2049));
    return checks;
}
