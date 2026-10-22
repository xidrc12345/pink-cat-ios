#include "MiniApple.h"
#include "AudioPolicy.h"
#include "PanelPolicy.h"

#define A32(p) __atomic_load_n((p),__ATOMIC_ACQUIRE)
#define A64(p) __atomic_load_n((p),__ATOMIC_ACQUIRE)
#define W32(p,v) __atomic_store_n((p),(v),__ATOMIC_RELEASE)
#define W64(p,v) __atomic_store_n((p),(v),__ATOMIC_RELEASE)

/* Fixed-width, pointer-free telemetry. MCP can resolve this exported symbol. */
typedef struct {
    u32 magic,schema,size,sequence;
    i32 targetKbps,requestedKbps,sdkReadbackKbps,originalKbps;
    u32 sdkCompatible,hooksReady,publishing,qualitySamples;
    u64 sdkKbpsMilli,sendBytes,deltaKbpsMilli,sendFPSMilli,captureFPSMilli,lossPPM;
    i32 rttMs,status;
    u64 qualityTimestampMs,requestCount;
    u32 targetGeneration,appliedGeneration,statusWrites,lastError;
    char sdkVersion[32];
} PCState;
__attribute__((visibility("default"))) PCState PinkCatAudioState={
    .magic=0x50434131,.schema=1,.size=sizeof(PCState),.targetKbps=0,
    .requestedKbps=-1,.sdkReadbackKbps=-1,.originalKbps=-1,.rttMs=-1
};

#include "NativeCodec.h"
static const int chosenMode=0;
static int activeRate=0;

enum {PCOriginal=0,PCPending=1,PCRequested=2,PCMeasured=3,PCMismatch=4,PCUnsupported=5,PCException=6};
typedef struct {int rate;usize channel,codec;_Bool valid;} PCConfig;
static PCConfig original={0};
static unsigned long nestingKey;
static int nestingReady=0,didOverride=0;
static int applying=0,installFinished=0,retryCount=0;
static u64 streamHash=0,previousBytes=0,previousTime=0;
static id controller=0,floating=0,panel=0,panelScroll=0,timer=0,statusPath=0;
static id brandTitle,subtitle,closeButton,badge,segmentBox,statsBox,contactBox;
static id valueLabel,unitLabel,stateLabel,targetLabel,modeLabel,detailLabel;
static id statsTitle,targetCaption,modeCaption,divider,tipsTitle,tipOne,tipTwo,privacyLabel;
static id contactTitle,contactFooter,contactNames[2],contactCaptions[2],copyButtons[2];
static u64 copyUntil[2]={0};
static PCPanelLayout lastLayout={0};
static id rateButtons[PC_RATE_COUNT];
static int dirty=1,ticks=0;
static IMP oldSet1=0,oldSet2=0,oldStart1=0,oldStart2=0,oldStart3=0,oldStartScene=0,oldStop1=0,oldStop2=0,oldQuality=0;
static int Inside(void){return (int)(usize)pthread_getspecific(nestingKey);}
static void Enter(void){pthread_setspecific(nestingKey,(const void*)(usize)(Inside()+1));}
static void Leave(void){int n=Inside();pthread_setspecific(nestingKey,(const void*)(usize)(n>0?n-1:0));}

static void StateChanged(void){__atomic_add_fetch(&PinkCatAudioState.sequence,1,__ATOMIC_RELAXED);W32(&dirty,1);}
static u64 Now(void){double t=D(O(C("NSDate"),"date"),"timeIntervalSince1970");return t>0?(u64)(t*1000):0;}
static void Error(int value){W32(&PinkCatAudioState.lastError,value);W32(&PinkCatAudioState.status,PCException);StateChanged();}
static u64 HashString(id value){
    if(!value||!Kind(value,"NSString"))return 0;
    const unsigned char *p=(const unsigned char*)UTF8(value);u64 h=1469598103934665603ULL;
    if(!p)return 0;for(int i=0;i<2048&&p[i];i++){h^=p[i];h*=1099511628211ULL;}return h;
}
static _Bool SDKUuidMatches(void){
    static const unsigned char wanted[16]={0x06,0xdd,0xcb,0xa1,0x57,0x82,0x3d,0x86,0x86,0xca,0xc9,0x8b,0xa1,0x66,0xca,0x7e};
    for(u32 i=0;i<_dyld_image_count();i++){
        const char *name=_dyld_get_image_name(i);if(!name||!strstr(name,"/ZegoExpressEngine.framework/ZegoExpressEngine"))continue;
        const u32 *h=(const u32*)_dyld_get_image_header(i);if(!h||h[0]!=0xfeedfacf||h[4]>4096||h[5]>1048576)return 0;
        const unsigned char *p=(const unsigned char*)h+32,*end=p+h[5];
        for(u32 n=0;n<h[4]&&p+8<=end;n++){
            u32 cmd=*(const u32*)p,size=*(const u32*)(p+4);if(size<8||size>(usize)(end-p))return 0;
            if(cmd==0x1b&&size>=24){for(int j=0;j<16;j++)if(p[8+j]!=wanted[j])return 0;return 1;}p+=size;
        }
    }return 0;
}
static PCConfig ConfigValues(id cfg){
    PCConfig r={0};if(!cfg||!Kind(cfg,"ZegoAudioConfig"))return r;
    if(!Responds(cfg,"bitrate")||!Responds(cfg,"channel")||!Responds(cfg,"codecID"))return r;
    r.rate=I32(cfg,"bitrate");r.channel=(usize)I(cfg,"channel");r.codec=(usize)I(cfg,"codecID");
    r.valid=r.rate>0&&r.rate<=2000&&r.channel<=8&&r.codec<=128;return r;
}
static void RememberOriginal(id cfg){
    PCConfig c=ConfigValues(cfg);if(!c.valid)return;original=c;W32(&PinkCatAudioState.originalKbps,c.rate);
}
static id MakeConfig(PCConfig base,int target){
    if(!base.valid)return 0;id cfg=O(C("ZegoAudioConfig"),"new");if(!cfg)return 0;
    ((void(*)(id,SEL,i32))objc_msgSend)(cfg,S("setBitrate:"),target>0?PCBootstrapRate(target):base.rate);
    VI(cfg,"setChannel:",(long)(target?PCRequestedChannels(target,(int)base.channel):base.channel));VI(cfg,"setCodecID:",(long)(target?6:base.codec));return cfg;
}
static void Readback(id engine){
    id config=Responds(engine,"getAudioConfig")?O(engine,"getAudioConfig"):0;PCConfig c=ConfigValues(config);
    W32(&PinkCatAudioState.sdkReadbackKbps,c.valid?c.rate:-1);StateChanged();
}
static void MarkRequest(int rate){
    W32(&PinkCatAudioState.requestedKbps,rate);W32(&PinkCatAudioState.status,PCRequested);
    W32(&PinkCatAudioState.appliedGeneration,A32(&PinkCatAudioState.targetGeneration));
    __atomic_add_fetch(&PinkCatAudioState.requestCount,1,__ATOMIC_RELAXED);StateChanged();
}
static void HookSet1(id self,SEL cmd,id cfg){
    if(Inside()||!A32(&PinkCatAudioState.sdkCompatible)){((void(*)(id,SEL,id))oldSet1)(self,cmd,cfg);return;}
    Enter();id replacement=0;
    @try{
        RememberOriginal(cfg);int target=A32(&PinkCatAudioState.publishing)?activeRate:A32(&PinkCatAudioState.targetKbps);
        replacement=target?MakeConfig(ConfigValues(cfg),target):0;
        ((void(*)(id,SEL,id))oldSet1)(self,cmd,replacement?replacement:cfg);
        if(replacement)didOverride=1;MarkRequest(replacement?target:ConfigValues(cfg).rate);Readback(self);
    }@catch(id exception){Error(101);}@finally{Release(replacement);Leave();}
}
static void HookSet2(id self,SEL cmd,id cfg,usize channel){
    if(Inside()||channel!=0||!A32(&PinkCatAudioState.sdkCompatible)){((void(*)(id,SEL,id,usize))oldSet2)(self,cmd,cfg,channel);return;}
    Enter();id replacement=0;
    @try{
        RememberOriginal(cfg);int target=A32(&PinkCatAudioState.publishing)?activeRate:A32(&PinkCatAudioState.targetKbps);
        replacement=target?MakeConfig(ConfigValues(cfg),target):0;
        ((void(*)(id,SEL,id,usize))oldSet2)(self,cmd,replacement?replacement:cfg,channel);
        if(replacement)didOverride=1;MarkRequest(replacement?target:ConfigValues(cfg).rate);Readback(self);
    }@catch(id exception){Error(102);}@finally{Release(replacement);Leave();}
}
static void PreparePublish(id self,id stream){
    if(!A32(&PinkCatAudioState.sdkCompatible))return;
    @try{
        if(!original.valid&&Responds(self,"getAudioConfig"))RememberOriginal(O(self,"getAudioConfig"));
        int target=A32(&PinkCatAudioState.targetKbps);activeRate=target;NativeArm(target,chosenMode);
        W64(&PinkCatAudioState.qualityTimestampMs,0);
        id cfg=(target||didOverride)?MakeConfig(original,target):0;
        if(cfg){
            /* Keep the host's codec/channel and use the documented pre-publish timing. */
            @try{((void(*)(id,SEL,id))oldSet1)(self,S("setAudioConfig:"),cfg);didOverride=target!=0;MarkRequest(target?target:original.rate);Readback(self);}
            @finally{Release(cfg);}
        }
        W64(&streamHash,HashString(stream));previousBytes=0;previousTime=0;
        W32(&PinkCatAudioState.publishing,1);StateChanged();
    }@catch(id exception){Error(103);}
}
static void HookStart1(id self,SEL cmd,id stream){
    if(Inside()){((void(*)(id,SEL,id))oldStart1)(self,cmd,stream);return;}
    Enter();@try{PreparePublish(self,stream);((void(*)(id,SEL,id))oldStart1)(self,cmd,stream);}@finally{Leave();}
}
static void HookStart2(id self,SEL cmd,id stream,usize channel){
    if(Inside()||channel!=0){((void(*)(id,SEL,id,usize))oldStart2)(self,cmd,stream,channel);return;}
    Enter();@try{PreparePublish(self,stream);((void(*)(id,SEL,id,usize))oldStart2)(self,cmd,stream,channel);}@finally{Leave();}
}
static void HookStart3(id self,SEL cmd,id stream,id config,usize channel){
    if(Inside()||channel!=0){((void(*)(id,SEL,id,id,usize))oldStart3)(self,cmd,stream,config,channel);return;}
    Enter();@try{PreparePublish(self,stream);((void(*)(id,SEL,id,id,usize))oldStart3)(self,cmd,stream,config,channel);}@finally{Leave();}
}
static void HookStartScene(id self,SEL cmd,id scene,usize channel,id config){
    if(Inside()||channel!=0){((void(*)(id,SEL,id,usize,id))oldStartScene)(self,cmd,scene,channel,config);return;}
    Enter();@try{PreparePublish(self,0);((void(*)(id,SEL,id,usize,id))oldStartScene)(self,cmd,scene,channel,config);}@finally{Leave();}
}
static void Stopped(void){W32(&PinkCatAudioState.publishing,0);W64(&streamHash,0);W64(&nativeMain,0);StateChanged();}
static void HookStop1(id self,SEL cmd){((void(*)(id,SEL))oldStop1)(self,cmd);Stopped();}
static void HookStop2(id self,SEL cmd,usize channel){((void(*)(id,SEL,usize))oldStop2)(self,cmd,channel);if(channel==0)Stopped();}
static void ObserveQuality(id quality,id stream){
    if(!quality||!Kind(quality,"ZegoPublishStreamQuality"))return;
    u64 hash=A64(&streamHash);if(hash&&HashString(stream)!=hash)return;
    if(__atomic_exchange_n(&applying,1,__ATOMIC_ACQUIRE))return;
    @try{
        double kbps=D(quality,"audioKBPS"),bytes=D(quality,"audioSendBytes"),fps=D(quality,"audioSendFPS"),capture=D(quality,"audioCaptureFPS"),loss=D(quality,"packetLostRate");
        int rtt=I32(quality,"rtt");u64 now=Now();
        if(!PCMetricValid(kbps,20000)||!PCMetricValid(bytes,1e15)||!PCMetricValid(fps,1000)||!PCMetricValid(capture,1000)||!PCMetricValid(loss,1))return;
        double delta=previousTime&&now>previousTime?PCByteRate(bytes,(double)previousBytes,(double)(now-previousTime)):-1;
        W64(&PinkCatAudioState.sdkKbpsMilli,(u64)(kbps*1000));W64(&PinkCatAudioState.sendBytes,(u64)bytes);
        W64(&PinkCatAudioState.deltaKbpsMilli,delta>=0?(u64)(delta*1000):~0ULL);
        W64(&PinkCatAudioState.sendFPSMilli,(u64)(fps*1000));W64(&PinkCatAudioState.captureFPSMilli,(u64)(capture*1000));
        W64(&PinkCatAudioState.lossPPM,(u64)(loss*1000000));W32(&PinkCatAudioState.rttMs,rtt);
        __atomic_add_fetch(&PinkCatAudioState.qualitySamples,1,__ATOMIC_RELAXED);
        W64(&PinkCatAudioState.qualityTimestampMs,now);previousBytes=(u64)bytes;previousTime=now;
        int target=A32(&PinkCatAudioState.targetKbps);
        if(A32(&PinkCatAudioState.targetGeneration)==A32(&PinkCatAudioState.appliedGeneration))
            W32(&PinkCatAudioState.status,target>0?(kbps>=target*.90&&A32(&PinkCatNativeState.appliedBps)==192000?PCMeasured:PCMismatch):PCOriginal);
        StateChanged();
    }@catch(id exception){Error(104);}@finally{__atomic_store_n(&applying,0,__ATOMIC_RELEASE);}
}
static void HookQuality(id self,SEL cmd,id quality,id stream){
    ObserveQuality(quality,stream);((void(*)(id,SEL,id,id))oldQuality)(self,cmd,quality,stream);
}
static _Bool Hook(Class cls,const char *selector,const char *encoding,IMP replacement,IMP *originalImp){
    Method m=class_getInstanceMethod(cls,S(selector));if(!m)return 0;
    const char *actual=method_getTypeEncoding(m);if(!actual||strcmp(actual,encoding))return 0;
    *originalImp=method_setImplementation(m,replacement);return *originalImp!=0;
}
static void Install(void){
    if(installFinished)return;Class engine=objc_getClass("ZegoExpressEngine");if(!engine)return;
    @try{
        id version=O((id)engine,"getVersion");const char *v=version?UTF8(version):0;
        if(v)snprintf(PinkCatAudioState.sdkVersion,sizeof(PinkCatAudioState.sdkVersion),"%s",v);
        if(!v||strcmp(v,"3.25.0.51876")||!SDKUuidMatches()){
            W32(&PinkCatAudioState.status,PCUnsupported);installFinished=1;StateChanged();return;
        }
        if(!nestingReady){if(pthread_key_create(&nestingKey,0)){Error(203);installFinished=1;return;}nestingReady=1;}
        Method set1=class_getInstanceMethod(engine,S("setAudioConfig:")),set2=class_getInstanceMethod(engine,S("setAudioConfig:channel:"));
        if(!set1||!set2||strcmp(method_getTypeEncoding(set1),"v24@0:8@16")||strcmp(method_getTypeEncoding(set2),"v32@0:8@16Q24")){Error(201);installFinished=1;return;}
        W32(&PinkCatAudioState.sdkCompatible,1);
        int installed=0;
        installed+=Hook(engine,"setAudioConfig:","v24@0:8@16",(IMP)HookSet1,&oldSet1);
        installed+=Hook(engine,"setAudioConfig:channel:","v32@0:8@16Q24",(IMP)HookSet2,&oldSet2);
        installed+=Hook(engine,"startPublishingStream:","v24@0:8@16",(IMP)HookStart1,&oldStart1);
        installed+=Hook(engine,"startPublishingStream:channel:","v32@0:8@16Q24",(IMP)HookStart2,&oldStart2);
        installed+=Hook(engine,"startPublishingStream:config:channel:","v40@0:8@16@24Q32",(IMP)HookStart3,&oldStart3);
        installed+=Hook(engine,"startPublishingStreamInScene:channel:config:","v40@0:8@16Q24@32",(IMP)HookStartScene,&oldStartScene);
        installed+=Hook(engine,"stopPublishingStream","v16@0:8",(IMP)HookStop1,&oldStop1);
        installed+=Hook(engine,"stopPublishingStream:","v24@0:8Q16",(IMP)HookStop2,&oldStop2);
        Class wrapper=objc_getClass("ZegoSDK");
        if(wrapper)installed+=Hook(wrapper,"onPublisherQualityUpdate:streamID:","v32@0:8@16@24",(IMP)HookQuality,&oldQuality);
        NativeInstall();W32(&PinkCatAudioState.hooksReady,installed);installFinished=1;StateChanged();
    }@catch(id exception){Error(202);installFinished=1;}
}

static id Label(id parent,const char *text,PCRect frame,double size,_Bool bold){
    id l=O(C("UILabel"),"new");SetFrame(l,frame);V1(l,"setText:",Str(text));
    V1(l,"setFont:",Font(size,bold?.23:0));V1(l,"setTextColor:",Color(.40,.19,.30,1));VI(l,"setNumberOfLines:",0);
    VB(l,"setAdjustsFontSizeToFitWidth:",1);VD(l,"setMinimumScaleFactor:",.8);
    V1(parent,"addSubview:",l);Release(l);return l;
}
static id Button(id parent,const char *text,PCRect frame,const char *action,int tag){
    id b=((id(*)(id,SEL,long))objc_msgSend)(C("UIButton"),S("buttonWithType:"),1);SetFrame(b,frame);VI(b,"setTag:",tag);
    ((void(*)(id,SEL,id,usize))objc_msgSend)(b,S("setTitle:forState:"),Str(text),0);
    ((void(*)(id,SEL,id,usize))objc_msgSend)(b,S("setTitleColor:forState:"),Color(.52,.20,.35,1),0);
    V1(O(b,"titleLabel"),"setFont:",Font(12,.23));V1(b,"setBackgroundColor:",Color(1,.90,.94,1));VD(O(b,"layer"),"setCornerRadius:",11);
    ((void(*)(id,SEL,id,SEL,usize))objc_msgSend)(b,S("addTarget:action:forControlEvents:"),controller,S(action),1UL<<6);
    V1(parent,"addSubview:",b);return b;
}
static id Surface(id parent,double radius,_Bool border){
    id v=O(C("UIView"),"new");V1(v,"setBackgroundColor:",Color(1,.995,1,1));
    VD(O(v,"layer"),"setCornerRadius:",radius);
    if(border){VD(O(v,"layer"),"setBorderWidth:",.6);V1(O(v,"layer"),"setBorderColor:",O(Color(.96,.86,.90,1),"CGColor"));}
    V1(parent,"addSubview:",v);Release(v);return v;
}
static void Muted(id label){V1(label,"setTextColor:",Color(.56,.49,.54,1));}
static void Center(id label){VI(label,"setTextAlignment:",1);}
static void Right(id label){VI(label,"setTextAlignment:",2);}
static void SetTitle(id button,const char *text){((void(*)(id,SEL,id,usize))objc_msgSend)(button,S("setTitle:forState:"),Str(text),0);}
static void TitleColor(id button,id color){((void(*)(id,SEL,id,usize))objc_msgSend)(button,S("setTitleColor:forState:"),color,0);}
static id KeyWindow(id windows){
    id fallback=0;usize count=(usize)I(windows,"count");
    for(usize i=0;i<count;i++){id w=At(windows,i);if(B(w,"isHidden")||D(w,"windowLevel")!=0)continue;if(B(w,"isKeyWindow"))return w;if(!fallback)fallback=w;}
    return fallback;
}
static id Window(void){
    id app=O(C("UIApplication"),"sharedApplication"),scenes=O(O(app,"connectedScenes"),"allObjects");
    for(usize i=0;i<(usize)I(scenes,"count");i++){
        id scene=At(scenes,i);if(I(scene,"activationState")!=0||!Responds(scene,"windows"))continue;
        id w=KeyWindow(O(scene,"windows"));if(w)return w;
    }
    return KeyWindow(O(app,"windows"));
}
static void ShowText(id label,const char *text){if(label)V1(label,"setText:",Str(text));}
static void RefreshUI(void){
    if(!panel)return;
    PCPanelInput i={
        .target=A32(&PinkCatAudioState.targetKbps),.publishing=A32(&PinkCatAudioState.publishing),
        .finished=installFinished,.compatible=A32(&PinkCatAudioState.sdkCompatible),.status=A32(&PinkCatAudioState.status),
        .lastError=A32(&PinkCatAudioState.lastError),.nativeError=A32(&PinkCatNativeState.error),
        .activeTarget=A32(&PinkCatNativeState.activeTarget),.layoutReady=A32(&PinkCatNativeState.layoutReady),
        .appliedBps=A32(&PinkCatNativeState.appliedBps),.vbr=A32(&PinkCatNativeState.vbr),.useCbr=A32(&PinkCatNativeState.useCbr),
        .channels=A32(&PinkCatNativeState.channels),.readback=A32(&PinkCatAudioState.sdkReadbackKbps),
        .targetGeneration=A32(&PinkCatAudioState.targetGeneration),.appliedGeneration=A32(&PinkCatAudioState.appliedGeneration),
        .timestamp=A64(&PinkCatAudioState.qualityTimestampMs),.now=Now(),.kbpsMilli=A64(&PinkCatAudioState.sdkKbpsMilli),
        .rtt=A32(&PinkCatAudioState.rttMs),.lossPPM=A64(&PinkCatAudioState.lossPPM)};
    PCPanelText text=PCMakePanelText(i);
    ShowText(valueLabel,text.value);ShowText(badge,text.badge);ShowText(stateLabel,text.state);
    ShowText(targetLabel,text.target);ShowText(modeLabel,text.mode);ShowText(detailLabel,text.detail);
    V1(stateLabel,"setBackgroundColor:",text.warning?Color(1,.94,.86,1):Color(.96,.94,.96,1));
    V1(stateLabel,"setTextColor:",text.warning?Color(.61,.35,.13,1):Color(.48,.40,.46,1));
    for(int j=0;j<PC_RATE_COUNT;j++)if(rateButtons[j]){
        _Bool selected=PCRates[j]==i.target;
        V1(rateButtons[j],"setBackgroundColor:",selected?Color(.85,.39,.57,1):Color(1,.98,.99,1));
        TitleColor(rateButtons[j],selected?Color(1,1,1,1):Color(.42,.22,.33,1));
        VI(rateButtons[j],"setAccessibilityTraits:",(1UL<<0)|(selected?(1UL<<2):0));
    }
    for(int j=0;j<2;j++)SetTitle(copyButtons[j],copyUntil[j]>i.now?"已复制":"复制");
}
static void SaveStatus(void){
    if(!statusPath){
        id dir=O1(NSHomeDirectory(),"stringByAppendingPathComponent:",Str("Documents/PinkCatAudio"));id error=0;
        _Bool ok=((_Bool(*)(id,SEL,id,_Bool,id,id*))objc_msgSend)(O(C("NSFileManager"),"defaultManager"),S("createDirectoryAtPath:withIntermediateDirectories:attributes:error:"),dir,1,0,&error);
        if(!ok){W32(&PinkCatAudioState.lastError,301);return;}
        statusPath=Retain(O1(dir,"stringByAppendingPathComponent:",Str("status.json")));
    }
    id dict=O(C("NSMutableDictionary"),"new");
    @try{
        Dict(dict,"plugin",Str("pink cat iOS 1.0.0"));Dict(dict,"schema",Number(1));Dict(dict,"sdkVersion",Str(PinkCatAudioState.sdkVersion));
        Dict(dict,"targetKbps",Number(A32(&PinkCatAudioState.targetKbps)));Dict(dict,"requestedKbps",Number(A32(&PinkCatAudioState.requestedKbps)));
        Dict(dict,"sdkReadbackKbps",Number(A32(&PinkCatAudioState.sdkReadbackKbps)));Dict(dict,"originalKbps",Number(A32(&PinkCatAudioState.originalKbps)));
        Dict(dict,"sdkCompatible",Number(A32(&PinkCatAudioState.sdkCompatible)));Dict(dict,"hooksReady",Number(A32(&PinkCatAudioState.hooksReady)));
        Dict(dict,"publishing",Number(A32(&PinkCatAudioState.publishing)));Dict(dict,"qualitySamples",Number(A32(&PinkCatAudioState.qualitySamples)));
        Dict(dict,"sdkKbpsMilli",Number(A64(&PinkCatAudioState.sdkKbpsMilli)));Dict(dict,"audioSendBytes",Number(A64(&PinkCatAudioState.sendBytes)));
        u64 delta=A64(&PinkCatAudioState.deltaKbpsMilli);Dict(dict,"byteDeltaKbpsMilli",Number(delta==~0ULL?-1:(i64)delta));
        Dict(dict,"sendFPSMilli",Number(A64(&PinkCatAudioState.sendFPSMilli)));Dict(dict,"captureFPSMilli",Number(A64(&PinkCatAudioState.captureFPSMilli)));
        Dict(dict,"lossPPM",Number(A64(&PinkCatAudioState.lossPPM)));Dict(dict,"rttMs",Number(A32(&PinkCatAudioState.rttMs)));
        Dict(dict,"qualityTimestampMs",Number(A64(&PinkCatAudioState.qualityTimestampMs)));Dict(dict,"status",Number(A32(&PinkCatAudioState.status)));
        Dict(dict,"targetGeneration",Number(A32(&PinkCatAudioState.targetGeneration)));Dict(dict,"appliedGeneration",Number(A32(&PinkCatAudioState.appliedGeneration)));
        Dict(dict,"requestCount",Number(A64(&PinkCatAudioState.requestCount)));Dict(dict,"lastError",Number(A32(&PinkCatAudioState.lastError)));
        Dict(dict,"nativeInstalled",Number(A32(&PinkCatNativeState.installed)));Dict(dict,"nativeLayoutReady",Number(A32(&PinkCatNativeState.layoutReady)));Dict(dict,"nativeError",Number(A32(&PinkCatNativeState.error)));Dict(dict,"nativeRequestedCount",Number(A32(&PinkCatNativeState.rawRequests)));
        Dict(dict,"nativeUserBps",Number(A32(&PinkCatNativeState.userBps)));Dict(dict,"nativeAppliedBps",Number(A32(&PinkCatNativeState.appliedBps)));Dict(dict,"nativeSourceBps",Number(A32(&PinkCatNativeState.sourceBps)));Dict(dict,"nativeSourceRequestedBps",Number(A32(&PinkCatNativeState.sourceRequestedBps)));Dict(dict,"nativeWrapperBps",Number(A32(&PinkCatNativeState.wrapperBps)));
        Dict(dict,"nativeVbr",Number(A32(&PinkCatNativeState.vbr)));Dict(dict,"nativeUseCbr",Number(A32(&PinkCatNativeState.useCbr)));Dict(dict,"nativeConstrained",Number(A32(&PinkCatNativeState.constrained)));Dict(dict,"nativeDtx",Number(A32(&PinkCatNativeState.dtx)));Dict(dict,"nativeSampleRate",Number(A32(&PinkCatNativeState.sampleRate)));Dict(dict,"nativeChannels",Number(A32(&PinkCatNativeState.channels)));Dict(dict,"nativeFrameSamples",Number(A32(&PinkCatNativeState.frameSamples)));Dict(dict,"nativeEncodeCalls",Number(A64(&PinkCatNativeState.encodeCalls)));Dict(dict,"nativeControlCalls",Number(A64(&PinkCatNativeState.controlCalls)));Dict(dict,"selectedMode",Str(chosenMode?"CVBR":"CBR"));
        Dict(dict,"controlMode",Str("192 kbps only; public SDK config plus guarded Opus CBR; no native bitrate override"));
        id error=0;id data=((id(*)(id,SEL,id,usize,id*))objc_msgSend)(C("NSJSONSerialization"),S("dataWithJSONObject:options:error:"),dict,1,&error);
        _Bool ok=data&&((_Bool(*)(id,SEL,id,usize,id*))objc_msgSend)(data,S("writeToFile:options:error:"),statusPath,1,&error);
        if(ok)__atomic_add_fetch(&PinkCatAudioState.statusWrites,1,__ATOMIC_RELAXED);else W32(&PinkCatAudioState.lastError,302);
    }@finally{Release(dict);}
}
static void Toggle(id self,SEL cmd,id sender){
    (void)self;(void)cmd;(void)sender;if(!panel)return;
    _Bool hidden=B(panel,"isHidden");VB(panel,"setHidden:",!hidden);VB(floating,"setHidden:",hidden);
    if(hidden){RefreshUI();V1(O(panel,"superview"),"bringSubviewToFront:",panel);}
}
static void SelectRate(id self,SEL cmd,id sender){
    (void)self;(void)cmd;int rate=(int)I(sender,"tag");if(!PCRateAllowed(rate))return;
    if(rate==A32(&PinkCatAudioState.targetKbps))return;
    W32(&PinkCatAudioState.targetKbps,rate);__atomic_add_fetch(&PinkCatAudioState.targetGeneration,1,__ATOMIC_RELAXED);
    W32(&PinkCatAudioState.status,PCPending);StateChanged();
    id defaults=O(C("NSUserDefaults"),"standardUserDefaults");
    ((void(*)(id,SEL,long,id))objc_msgSend)(defaults,S("setInteger:forKey:"),(long)rate,Str("PinkCatAudio.targetKbps.192.v1"));
    RefreshUI();SaveStatus();
}
static void CopyContact(id self,SEL cmd,id sender){
    (void)self;(void)cmd;int tag=(int)I(sender,"tag");const char *value=PCContact(tag);if(!value)return;
    @try{
        /* Explicit tap only. Never read the user's pasteboard or open another app. */
        id board=O(C("UIPasteboard"),"generalPasteboard");if(!board)return;V1(board,"setString:",Str(value));
        copyUntil[tag-1]=Now()+2200;SetTitle(sender,"已复制");
        id feedback=O(C("UISelectionFeedbackGenerator"),"new");V(feedback,"selectionChanged");Release(feedback);
    }@catch(id exception){SetTitle(sender,"未复制");}
}
static PCInsets SafeInsets(id w){return ((PCInsets(*)(id,SEL))objc_msgSend)(w,S("safeAreaInsets"));}
static void ClampFloating(id w){
    if(!floating)return;PCRect f=Frame(floating),b=Bounds(w);PCInsets in=SafeInsets(w);
    f.origin.x=PCClamp(f.origin.x,in.left+8,b.size.width-in.right-f.size.width-8);
    f.origin.y=PCClamp(f.origin.y,in.top+8,b.size.height-in.bottom-f.size.height-8);
    SetFrame(floating,f);
}
static void Drag(id self,SEL cmd,id pan){
    (void)self;(void)cmd;id parent=O(floating,"superview");if(!parent)return;
    PCPoint change=((PCPoint(*)(id,SEL,id))objc_msgSend)(pan,S("translationInView:"),parent);PCRect f=Frame(floating);
    f.origin.x+=change.x;f.origin.y+=change.y;
    SetFrame(floating,f);ClampFloating(parent);PCPoint zero={0,0};((void(*)(id,SEL,PCPoint,id))objc_msgSend)(pan,S("setTranslation:inView:"),zero,parent);
}
static void Place(id v,double x,double y,double w,double h,double font,_Bool bold){
    SetFrame(v,Rect(x,y,w,h));if(font>0)V1(v,"setFont:",Font(font,bold?.23:0));
}
static void PlaceBox(id v,PCBox b){SetFrame(v,Rect(b.x,b.y,b.w,b.h));}
static double TextScale(void){
    id metrics=O(C("UIFontMetrics"),"defaultMetrics");
    double size=((double(*)(id,SEL,double))objc_msgSend)(metrics,S("scaledValueForValue:"),12.0);
    return PCClamp(size/12.0,1,1.35);
}
static void LayoutPanel(PCPanelLayout l){
    double w=l.sheet.w,s=l.scale,cw=l.stats.w;PlaceBox(panel,l.sheet);PlaceBox(panelScroll,l.scroll);
    ((void(*)(id,SEL,PCSize))objc_msgSend)(panelScroll,S("setContentSize:"),(PCSize){w,l.contentHeight});
    Place(brandTitle,18,9*s,w-80,28*s,21*s,1);Place(subtitle,18,38*s,w-124,19*s,11*s,0);
    Place(closeButton,w-50,4*s,44,44,0,0);Place(badge,w-106,40*s,88,19*s,10*s,1);
    PlaceBox(segmentBox,l.segment);double half=(l.segment.w-8)/2;
    for(int j=0;j<2;j++){
        SetFrame(rateButtons[j],Rect(4+j*half,3,half,l.segment.h-6));
        V1(O(rateButtons[j],"titleLabel"),"setFont:",Font(12*s,.23));
    }
    PlaceBox(statsBox,l.stats);Place(statsTitle,16,9*s,85,22*s,12*s,1);
    double pill=PCClamp(cw*.4,86,118);
    Place(stateLabel,cw-pill-12,9*s,pill,26*s,10*s,0);
    Place(valueLabel,16,34*s,105,40*s,27*s,1);Place(unitLabel,122,49*s,cw-138,21*s,12*s,0);
    SetFrame(divider,Rect(16,78*s,cw-32,.5));
    Place(targetCaption,16,87*s,68,20*s,11*s,0);Place(targetLabel,90,87*s,cw-106,20*s,12*s,0);
    Place(modeCaption,16,110*s,68,20*s,11*s,0);Place(modeLabel,90,110*s,cw-106,20*s,12*s,0);
    Place(detailLabel,16,133*s,cw-32,20*s,9*s,0);
    double y=l.tips.y;Place(tipsTitle,16,y,w-32,20*s,13*s,1);
    Place(tipOne,16,y+25*s,w-32,20*s,11*s,0);Place(tipTwo,16,y+48*s,w-32,30*s,11*s,0);
    Place(privacyLabel,16,y+80*s,w-32,24*s,10*s,0);
    PlaceBox(contactBox,l.contact);cw=l.contact.w;
    Place(contactTitle,14,8*s,cw-28,22*s,13*s,1);
    for(int j=0;j<2;j++){
        double rowY=(33+j*44)*s;
        Place(contactCaptions[j],14,rowY,34,44*s,11*s,0);
        Place(contactNames[j],49,rowY,cw-112,44*s,12*s,1);
        SetFrame(copyButtons[j],Rect(cw-60,rowY,48,44*s));
        V1(O(copyButtons[j],"titleLabel"),"setFont:",Font(11*s,.23));
    }
    Place(contactFooter,12,126*s,cw-24,26*s,9*s,0);
    lastLayout=l;
}
static void BuildPanel(id w,PCRect bounds){
    floating=Retain(Button(w,"pink cat",Rect(bounds.size.width-110,140,98,44),"toggle:",0));
    V1(floating,"setAccessibilityLabel:",Str("pink cat，打开音频面板"));
    VD(O(floating,"layer"),"setCornerRadius:",22);V1(floating,"setBackgroundColor:",Color(.99,.80,.88,.98));
    V1(O(floating,"titleLabel"),"setFont:",Font(13,.23));
    id pan=O(C("UIPanGestureRecognizer"),"alloc");pan=((id(*)(id,SEL,id,SEL))objc_msgSend)(pan,S("initWithTarget:action:"),controller,S("drag:"));V1(floating,"addGestureRecognizer:",pan);Release(pan);
    panel=O(C("UIView"),"new");V1(panel,"setBackgroundColor:",Color(1,.975,.986,1));
    VD(O(panel,"layer"),"setCornerRadius:",24);VD(O(panel,"layer"),"setBorderWidth:",.6);
    V1(O(panel,"layer"),"setBorderColor:",O(Color(.96,.82,.88,1),"CGColor"));
    V1(O(panel,"layer"),"setShadowColor:",O(Color(.55,.28,.41,1),"CGColor"));
    ((void(*)(id,SEL,float))objc_msgSend)(O(panel,"layer"),S("setShadowOpacity:"),.12f);
    VD(O(panel,"layer"),"setShadowRadius:",20);
    ((void(*)(id,SEL,PCSize))objc_msgSend)(O(panel,"layer"),S("setShadowOffset:"),(PCSize){0,5});
    brandTitle=Label(panel,"pink cat",Rect(0,0,0,0),21,1);
    subtitle=Label(panel,"移动端音频增强",Rect(0,0,0,0),11,0);Muted(subtitle);
    closeButton=Button(panel,"×",Rect(0,0,44,44),"toggle:",0);
    V1(closeButton,"setBackgroundColor:",Color(1,.975,.986,1));V1(O(closeButton,"titleLabel"),"setFont:",Font(23,0));
    V1(closeButton,"setAccessibilityLabel:",Str("收起 pink cat 面板"));
    badge=Label(panel,"192 CBR",Rect(0,0,0,0),10,1);Center(badge);V1(badge,"setBackgroundColor:",Color(1,.90,.94,1));
    VD(O(badge,"layer"),"setCornerRadius:",9);VB(badge,"setClipsToBounds:",1);
    panelScroll=O(C("UIScrollView"),"new");VB(panelScroll,"setClipsToBounds:",1);VB(panelScroll,"setDelaysContentTouches:",0);
    VI(panelScroll,"setContentInsetAdjustmentBehavior:",2);VB(panelScroll,"setAlwaysBounceVertical:",0);
    VD(O(panelScroll,"layer"),"setCornerRadius:",20);V1(panel,"addSubview:",panelScroll);Release(panelScroll);
    segmentBox=Surface(panelScroll,14,1);
    rateButtons[0]=Button(segmentBox,"恢复原版",Rect(0,0,0,0),"rate:",0);
    rateButtons[1]=Button(segmentBox,"192 kbps · CBR",Rect(0,0,0,0),"rate:",192);
    statsBox=Surface(panelScroll,17,1);
    statsTitle=Label(statsBox,"实际发送",Rect(0,0,0,0),12,1);
    valueLabel=Label(statsBox,"--",Rect(0,0,0,0),27,1);unitLabel=Label(statsBox,"kbps",Rect(0,0,0,0),12,0);Muted(unitLabel);
    stateLabel=Label(statsBox,"等待上麦",Rect(0,0,0,0),10,0);Center(stateLabel);VD(O(stateLabel,"layer"),"setCornerRadius:",12);VB(stateLabel,"setClipsToBounds:",1);
    divider=Surface(statsBox,0,0);V1(divider,"setBackgroundColor:",Color(.94,.90,.93,1));
    targetCaption=Label(statsBox,"目标码率",Rect(0,0,0,0),11,0);Muted(targetCaption);
    modeCaption=Label(statsBox,"编码模式",Rect(0,0,0,0),11,0);Muted(modeCaption);
    targetLabel=Label(statsBox,"192 kbps",Rect(0,0,0,0),12,0);Right(targetLabel);
    modeLabel=Label(statsBox,"等待生效",Rect(0,0,0,0),12,0);Right(modeLabel);
    detailLabel=Label(statsBox,"上麦后显示实时发送统计",Rect(0,0,0,0),9,0);Muted(detailLabel);
    tipsTitle=Label(panelScroll,"使用提示",Rect(0,0,0,0),13,1);
    tipOne=Label(panelScroll,"· 切换后下麦再上麦生效",Rect(0,0,0,0),11,0);
    tipTwo=Label(panelScroll,"· 目标码率不代表实时发送，弱网可能下降",Rect(0,0,0,0),11,0);
    privacyLabel=Label(panelScroll,"不录音 · 不放大麦克风 · 保持原声道",Rect(0,0,0,0),10,0);Muted(privacyLabel);
    contactBox=Surface(panelScroll,17,1);V1(contactBox,"setBackgroundColor:",Color(1,.935,.963,1));
    contactTitle=Label(contactBox,"PC 正式版请联系",Rect(0,0,0,0),13,1);
    for(int j=0;j<2;j++){
        contactCaptions[j]=Label(contactBox,"微信",Rect(0,0,0,0),11,0);Muted(contactCaptions[j]);
        contactNames[j]=Label(contactBox,PCContact(j+1),Rect(0,0,0,0),12,1);
        copyButtons[j]=Button(contactBox,"复制",Rect(0,0,0,0),"copyContact:",j+1);
        V1(copyButtons[j],"setBackgroundColor:",Color(1,.98,.99,1));
        char accessibility[100];snprintf(accessibility,sizeof(accessibility),"复制微信 %s",PCContact(j+1));
        V1(copyButtons[j],"setAccessibilityLabel:",Str(accessibility));
    }
    contactFooter=Label(contactBox,"移动端免费开源 · PC 版独立提供",Rect(0,0,0,0),9,0);Muted(contactFooter);Center(contactFooter);
    VB(panel,"setHidden:",1);
}
static void AttachUI(void){
    id w=Window();if(!w)return;PCRect bounds=Bounds(w);PCInsets in=SafeInsets(w);
    PCPanelLayout l=PCMakePanelLayout(bounds.size.width,bounds.size.height,in.top,in.left,in.bottom,in.right,TextScale());
    if(l.sheet.w<=0)return;
    if(!floating)BuildPanel(w,bounds);
    _Bool sameWindow=O(floating,"superview")==w&&O(panel,"superview")==w;
    if(!sameWindow){V(floating,"removeFromSuperview");V(panel,"removeFromSuperview");V1(w,"addSubview:",floating);V1(w,"addSubview:",panel);}
    if(!sameWindow||lastLayout.sheet.x!=l.sheet.x||lastLayout.sheet.y!=l.sheet.y||lastLayout.sheet.w!=l.sheet.w||lastLayout.sheet.h!=l.sheet.h||lastLayout.scale!=l.scale){LayoutPanel(l);ClampFloating(w);}
}
static void Tick(id self,SEL cmd,id sender){
    (void)self;(void)cmd;(void)sender;
    @try{
        if(!installFinished&&retryCount++<60&&!A32(&PinkCatAudioState.lastError))Install();NativeTick();
        if(I(O(C("UIApplication"),"sharedApplication"),"applicationState")==0){AttachUI();if(panel&&!B(panel,"isHidden"))RefreshUI();}
        ticks++;if(ticks%3==0&&__atomic_exchange_n(&dirty,0,__ATOMIC_ACQ_REL))SaveStatus();
    }@catch(id exception){W32(&PinkCatAudioState.lastError,303);}
}
static void Initialize(void *unused){
    (void)unused;id pool=O(C("NSAutoreleasePool"),"new");
    @try{
        const char *bundle=UTF8(O(O(C("NSBundle"),"mainBundle"),"bundleIdentifier"));if(!bundle||strcmp(bundle,"com.yiyou.tt"))return;
        if(objc_getClass("PinkCatAudioControllerMobileV1"))return;
        Class cls=objc_allocateClassPair((Class)C("NSObject"),"PinkCatAudioControllerMobileV1",0);if(!cls)return;
        class_addMethod(cls,S("toggle:"),(IMP)Toggle,"v24@0:8@16");class_addMethod(cls,S("rate:"),(IMP)SelectRate,"v24@0:8@16");
        class_addMethod(cls,S("copyContact:"),(IMP)CopyContact,"v24@0:8@16");
        class_addMethod(cls,S("drag:"),(IMP)Drag,"v24@0:8@16");class_addMethod(cls,S("tick:"),(IMP)Tick,"v24@0:8@16");objc_registerClassPair(cls);controller=O((id)cls,"new");
        id saved=O1(O(C("NSUserDefaults"),"standardUserDefaults"),"objectForKey:",Str("PinkCatAudio.targetKbps.192.v1"));
        int rate=PCSavedRate(Kind(saved,"NSNumber"),Kind(saved,"NSNumber")?(int)I(saved,"integerValue"):192);
        W32(&PinkCatAudioState.targetKbps,rate);W32(&PinkCatAudioState.targetGeneration,1);W32(&PinkCatAudioState.status,rate?PCPending:PCOriginal);
        if(objc_getClass("PinkCatAudioController192V1")||objc_getClass("PinkCatAudioControllerTEST01")||objc_getClass("PinkCatAudioControllerTEST02")){W32(&PinkCatAudioState.status,PCUnsupported);W32(&PinkCatAudioState.lastError,401);installFinished=1;}else Install();AttachUI();SaveStatus();
        timer=Retain(((id(*)(id,SEL,double,id,SEL,id,_Bool))objc_msgSend)(C("NSTimer"),S("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),2.0,controller,S("tick:"),0,1));
    }@catch(id exception){Error(304);}@finally{Release(pool);}
}
__attribute__((constructor)) static void LoadPinkCatAudio(void){OnMain(Initialize,0);}
