#ifndef PC_NATIVE_CODEC_H
#define PC_NATIVE_CODEC_H
#include "NativePolicy.h"
#include "NativeLayout.h"
extern u32 mach_task_self_;
extern int mach_vm_read_overwrite(u32,u64,u64,u64,u64*);
extern int mach_vm_region(u32,u64*,u64*,int,int*,u32*,u32*);
extern int mach_port_deallocate(u32,u32);
typedef void (*PCEncodeFn)(void*,void*,int);
typedef int (*PCOpusCtl)(void*,int,...);
typedef struct {
    u32 magic,schema,installed,layoutReady;
    i32 activeTarget,sourceIndex,sampleRate,channels,frameSamples,pcmBytes;
    i32 userBps,wrapperBps,sourceBps,sourceRequestedBps,vbr,useCbr,constrained,dtx;
    i32 appliedBps,error,rawRequests,mode;u64 encodeCalls,controlCalls;
    u64 sdkBase,mainSource,codecState;
} PCNativeState;
__attribute__((visibility("default"))) PCNativeState PinkCatNativeState={.magic=0x50434e32,.schema=2,.sourceIndex=-1,.vbr=-1,.dtx=-1};
static u64 nativeBase=0,nativeMain=0;
static PCEncodeFn nativeOldEncode=0;
static struct {u64 encoder,state;int vbr,constrained,dtx,modified;} nativeSaved={0};
static int NativeRead(u64 a,void *out,usize n){
    u64 got=0;return a>=0x100000000ULL&&a<0x8000000000ULL&&n&&n<=4096&&mach_vm_read_overwrite(mach_task_self_,a,n,(u64)out,&got)==0&&got==n;
}
static u64 NativePtr(u64 a){u64 p=0;if(!NativeRead(a,&p,8)||p%8||p<0x100000000ULL||p>=0x8000000000ULL)return 0;return p;}
static int NativeInt(u64 a,int *out){return NativeRead(a,out,4);}
static int NativeRW(u64 a,usize n){
    u64 p=a,z=0;int info[32]={0};u32 count=32,object=0;
    int result=mach_vm_region(mach_task_self_,&p,&z,9,info,&count,&object);
    if(object)mach_port_deallocate(mach_task_self_,object);
    return !result&&count>=2&&(info[0]&3)==3&&!(info[0]&4)&&p<=a&&a-p<=z&&n<=z-(a-p);
}
static int NativeGuard(u64 offset,const unsigned char *expected,usize n){
    unsigned char found[64];if(n>sizeof(found)||!NativeRead(nativeBase+offset,found,n))return 0;
    for(usize i=0;i<n;i++)if(found[i]!=expected[i])return 0;return 1;
}
static void NativeProblem(int e){W32(&PinkCatNativeState.error,e);}
static int NativeBind(void){
    u64 factory=NativePtr(nativeBase+0x1297980),ctx=factory?NativePtr(factory+0x20):0;
    u64 pair[2]={0};if(!ctx||!NativeRead(ctx+0xb0,pair,16)||pair[1]<pair[0]||pair[1]-pair[0]>256||(pair[1]-pair[0])%16)return 0;
    u64 channel=0;
    for(u64 at=pair[0];at<pair[1];at+=16){u64 p=NativePtr(at);int index=-1;if(p&&NativeInt(p+0x20,&index)&&index==0){channel=p;break;}}
    u64 engine=channel?NativePtr(channel+0x10):0,core=engine?NativePtr(engine+0x180):0,audio=core?NativePtr(core+0x68):0;
    if(!audio||NativePtr(audio)!=nativeBase+0xe09a50)return 0;
    u64 source=audio+0x221700;
    if(NativePtr(source)!=nativeBase+0xe0bd78)return 0;
    int index=-1,idA=-1,idB=-2;
    if(!NativeInt(source+0x160,&index)||index||!NativeInt(source+0x10,&idA)||!NativeInt(audio+0x4b8,&idB)||idA!=idB)return 0;
    W64(&nativeMain,source);W64(&PinkCatNativeState.mainSource,source);W32(&PinkCatNativeState.sourceIndex,index);W32(&PinkCatNativeState.layoutReady,1);return 1;
}
static void NativeArm(int target,int mode){
    W64(&nativeMain,0);
    W32(&PinkCatNativeState.activeTarget,target);W32(&PinkCatNativeState.appliedBps,0);W32(&PinkCatNativeState.layoutReady,0);
    W32(&PinkCatNativeState.error,0);W32(&PinkCatNativeState.mode,mode);
}
static void NativeTick(void){
    if(!A32(&PinkCatNativeState.installed)||!A32(&PinkCatAudioState.publishing))return;
    int target=A32(&PinkCatNativeState.activeTarget);if(target<=0)return;
    if(!A32(&PinkCatNativeState.layoutReady)&&!NativeBind())W32(&PinkCatNativeState.layoutReady,0);
}
static void NativeEncode(void *self,void *frame,int voiceGate){
    u64 me=(u64)self,source=A64(&nativeMain);int target=A32(&PinkCatNativeState.activeTarget);
    if(!target&&nativeSaved.modified&&nativeSaved.encoder==me&&nativeSaved.state==*(u64*)(me+0x10)){
        PCOpusCtl ctl=(PCOpusCtl)(nativeBase+0xa2df54);void *state=(void*)nativeSaved.state;
        int rc=ctl(state,4006,nativeSaved.vbr);rc|=ctl(state,4020,nativeSaved.constrained);rc|=ctl(state,4016,nativeSaved.dtx);
        if(rc)NativeProblem(415);else nativeSaved.modified=0;
    }
    if(!source||!target||!A32(&PinkCatAudioState.publishing)||*(u64*)(me+0x58)!=source||*(u64*)(source+0x158)!=me){nativeOldEncode(self,frame,voiceGate);return;}
    /* Invoked by the SDK on its own encoding thread; no timer-thread codec writes. */
    u64 state=*(u64*)(me+0x10);int fs=*(i32*)(me+0x18),ch=*(i32*)(me+0x1c),samples=*(i32*)(me+0x20),pcm=*(i32*)(me+0xf9c);
    if(!state||!PCNativeRateValid(target,ch)||!PCNativeShapeValid(fs,ch,*(i32*)(state+0x70),samples,pcm,*(i32*)(state+0x6c))){NativeProblem(412);nativeOldEncode(self,frame,voiceGate);return;}
    __atomic_add_fetch(&PinkCatNativeState.encodeCalls,1,__ATOMIC_RELAXED);
    int sourceRate=*(i32*)(source+0x198),user=*(i32*)(state+0xa4),want=target*1000,mode=A32(&PinkCatNativeState.mode);
    W64(&PinkCatNativeState.codecState,state);W32(&PinkCatNativeState.sampleRate,fs);W32(&PinkCatNativeState.channels,ch);W32(&PinkCatNativeState.frameSamples,samples);W32(&PinkCatNativeState.pcmBytes,pcm);
    W32(&PinkCatNativeState.sourceBps,sourceRate);W32(&PinkCatNativeState.sourceRequestedBps,*(i32*)(source+0x19c));W32(&PinkCatNativeState.wrapperBps,*(i32*)(me+0x24));
    int apply=PCNativeMayApply(target,sourceRate,user);
    if(apply){
        PCOpusCtl ctl=(PCOpusCtl)(nativeBase+0xa2df54);
        int vbr=mode?1:0;
        int changed=user!=want||*(i32*)(state+0x94)!=vbr||*(i32*)(state+0x3c)!=(1-vbr)||*(i32*)(state+0x98)!=1||*(i32*)(state+0xb8)!=0;
        if(changed){
            if(nativeSaved.encoder!=me||nativeSaved.state!=state||!nativeSaved.modified){
                nativeSaved.encoder=me;nativeSaved.state=state;nativeSaved.vbr=*(i32*)(state+0x94);nativeSaved.constrained=*(i32*)(state+0x98);nativeSaved.dtx=*(i32*)(state+0xb8);nativeSaved.modified=1;
            }
            int rc=ctl((void*)state,4006,vbr);rc|=ctl((void*)state,4020,1);rc|=ctl((void*)state,4016,0);
            __atomic_add_fetch(&PinkCatNativeState.controlCalls,1,__ATOMIC_RELAXED);
            if(rc||*(i32*)(state+0xa4)!=want||*(i32*)(state+0x94)!=vbr||*(i32*)(state+0x3c)!=(1-vbr)||*(i32*)(state+0x98)!=1||*(i32*)(state+0xb8)!=0){
                int restore=ctl((void*)state,4006,nativeSaved.vbr);restore|=ctl((void*)state,4020,nativeSaved.constrained);restore|=ctl((void*)state,4016,nativeSaved.dtx);
                if(!restore)nativeSaved.modified=0;NativeProblem(413);apply=0;W32(&PinkCatNativeState.appliedBps,0);
            }
        }
        if(apply){W32(&PinkCatNativeState.appliedBps,want);W32(&PinkCatNativeState.error,0);}
    }else W32(&PinkCatNativeState.appliedBps,0);
    W32(&PinkCatNativeState.userBps,*(i32*)(state+0xa4));W32(&PinkCatNativeState.vbr,*(i32*)(state+0x94));W32(&PinkCatNativeState.useCbr,*(i32*)(state+0x3c));W32(&PinkCatNativeState.constrained,*(i32*)(state+0x98));W32(&PinkCatNativeState.dtx,*(i32*)(state+0xb8));
    /* COpus' third argument only gates its silence path; PCM/frame data is unchanged. */
    nativeOldEncode(self,frame,apply&&!mode&&(voiceGate==0||voiceGate==1)?0:voiceGate);
}
static int NativeInstall(void){
    if(A32(&PinkCatNativeState.installed))return 1;
    for(u32 i=0;i<_dyld_image_count();i++){const char *p=_dyld_get_image_name(i);if(p&&strstr(p,"/ZegoExpressEngine.framework/ZegoExpressEngine")){nativeBase=(u64)_dyld_get_image_header(i);break;}}
    if(!nativeBase)return 0;W64(&PinkCatNativeState.sdkBase,nativeBase);
    for(usize i=0;i<PC_NATIVE_GUARD_COUNT;i++)if(!NativeGuard(PCNativeGuards[i].offset,PCNativeGuards[i].bytes,PCNativeGuards[i].length)){NativeProblem(410);return 0;}
    u64 table[13];if(!NativeRead(nativeBase+0xe075b0,table,sizeof(table))){NativeProblem(410);return 0;}
    for(int i=0;i<13;i++)if(table[i]!=nativeBase+PCNativeVtable[i]){NativeProblem(410);return 0;}
    u64 *slot=(u64*)(nativeBase+0xe075d0);
    if(!NativeRW((u64)slot,8)){NativeProblem(411);return 0;}
    nativeOldEncode=(PCEncodeFn)table[4];u64 expected=table[4];
    if(!__atomic_compare_exchange_n(slot,&expected,(u64)NativeEncode,0,__ATOMIC_RELEASE,__ATOMIC_ACQUIRE)){NativeProblem(414);return 0;}
    W32(&PinkCatNativeState.installed,1);return 1;
}
#endif
