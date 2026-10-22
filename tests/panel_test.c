typedef __SIZE_TYPE__ usize;
__declspec(dllexport) int (*pc_snprintf)(char*,usize,const char*,...)=0;
#define snprintf pc_snprintf
void *memcpy(void *to,const void *from,usize n){volatile unsigned char*d=to;const volatile unsigned char*s=from;for(usize k=0;k<n;k++)d[k]=s[k];return to;}
void *memset(void *to,int value,usize n){volatile unsigned char*d=to;for(usize k=0;k<n;k++)d[k]=(unsigned char)value;return to;}
#include "../src/PanelPolicy.h"
static int checks;
__declspec(dllexport) const char *failedExpression=0;
#define CHECK(x) do{checks++;if(!(x)){failedExpression=#x;return -__LINE__;}}while(0)
static int Eq(const char*a,const char*b){while(*a&&*a==*b){a++;b++;}return *a==*b;}
__declspec(dllexport) int run_tests(void){
    if(!pc_snprintf)return -1;
    const double widths[]={250,280,320,375,390,430,667,844,1024};
    const double heights[]={280,320,375,568,667,812,844,1024,1366};
    const double scales[]={1,1.15,1.35,2};
    for(int a=0;a<9;a++)for(int b=0;b<9;b++)for(int c=0;c<4;c++)for(int inset=0;inset<2;inset++){
        double t=inset?47:0,bt=inset?34:0;
        PCPanelLayout l=PCMakePanelLayout(widths[a],heights[b],t,0,bt,0,scales[c]);
        CHECK(l.sheet.w>0&&l.sheet.w<=340);CHECK(l.sheet.x>=12&&l.sheet.y>=t+12-0.01);
        CHECK(l.sheet.x+l.sheet.w<=widths[a]-12+.01);CHECK(l.sheet.y+l.sheet.h<=heights[b]-bt-12+.01);
        CHECK(l.scroll.h>0&&l.scroll.y==l.header);CHECK(l.scroll.y+l.scroll.h==l.sheet.h);
        CHECK(l.segment.y+l.segment.h<l.stats.y);CHECK(l.stats.y+l.stats.h<l.tips.y);
        CHECK(l.tips.y+l.tips.h<l.contact.y);CHECK(l.contact.y+l.contact.h<l.contentHeight);
        CHECK(l.stats.x+l.stats.w<=l.sheet.w-12+.01);CHECK(l.contact.w>0&&l.scale<=1.35);
    }
    CHECK(PCMakePanelLayout(200,800,0,0,0,0,1).sheet.w==0);
    CHECK(PCMakePanelLayout(390,160,0,0,0,0,1).sheet.w==0);
    PCPanelLayout landscape=PCMakePanelLayout(844,390,0,47,21,47,1);
    CHECK(landscape.sheet.x>=59&&landscape.sheet.x+landscape.sheet.w<=844-59);
    CHECK(landscape.contentHeight>landscape.scroll.h);
    CHECK(PCSavedRate(0,0)==192&&PCSavedRate(1,0)==0&&PCSavedRate(1,192)==192&&PCSavedRate(1,880)==192);
    CHECK(Eq(PCContact(1),"monnight1")&&Eq(PCContact(2),"aze-070130"));CHECK(!PCContact(0)&&!PCContact(3));
    PCPanelInput i={.target=192,.publishing=0,.finished=1,.compatible=1,.activeTarget=192,.targetGeneration=1,.appliedGeneration=1,.now=50000,.timestamp=49000,.kbpsMilli=191800,.rtt=18,.readback=192,.channels=1};
    PCPanelText t=PCMakePanelText(i);CHECK(Eq(t.value,"--")&&Eq(t.state,"等待上麦")&&!t.fresh);
    i.publishing=1;t=PCMakePanelText(i);CHECK(Eq(t.value,"191.8")&&Eq(t.mode,"CBR 未确认")&&t.warning);
    i.layoutReady=1;i.appliedBps=192000;i.vbr=0;i.useCbr=1;t=PCMakePanelText(i);
    CHECK(t.nativeConfirmed&&Eq(t.mode,"Opus · CBR")&&Eq(t.state,"发送接近目标")&&!t.warning);
    i.kbpsMilli=42000;t=PCMakePanelText(i);CHECK(Eq(t.state,"发送波动")&&Eq(t.value,"42.0"));
    i.now=62000;t=PCMakePanelText(i);CHECK(!t.fresh&&Eq(t.value,"--")&&Eq(t.state,"等待统计"));
    i.now=48000;t=PCMakePanelText(i);CHECK(!t.fresh&&Eq(t.value,"--"));
    i.now=50000;i.appliedGeneration=0;t=PCMakePanelText(i);CHECK(!t.nativeConfirmed&&Eq(t.mode,"等待生效")&&Eq(t.state,"待重新上麦"));
    i.target=0;t=PCMakePanelText(i);CHECK(Eq(t.badge,"原版")&&Eq(t.target,"跟随原版")&&Eq(t.mode,"等待生效"));
    i.appliedGeneration=1;t=PCMakePanelText(i);CHECK(Eq(t.mode,"跟随原版")&&Eq(t.state,"原版模式"));
    i.target=192;i.nativeError=413;t=PCMakePanelText(i);CHECK(t.warning&&!t.nativeConfirmed&&Eq(t.state,"编码未确认"));
    i.nativeError=0;i.lastError=401;t=PCMakePanelText(i);CHECK(t.warning&&Eq(t.state,"旧库冲突")&&Eq(t.mode,"未启用"));
    i.lastError=0;i.compatible=0;t=PCMakePanelText(i);CHECK(t.warning&&Eq(t.state,"版本不兼容")&&!t.nativeConfirmed);
    i.compatible=1;i.status=6;t=PCMakePanelText(i);CHECK(t.warning&&Eq(t.state,"操作异常"));
    i.status=0;i.channels=0;t=PCMakePanelText(i);CHECK(!t.nativeConfirmed);
    return checks;
}
