#ifndef PC_PANEL_POLICY_H
#define PC_PANEL_POLICY_H

/* Shared with host-side tests. No UIKit objects or borrowed sample data here. */
typedef struct {double x,y,w,h;} PCBox;
typedef struct {
    PCBox sheet,scroll,segment,stats,tips,contact;
    double header,contentHeight,scale;
} PCPanelLayout;
static double PCClamp(double v,double low,double high){return v<low?low:v>high?high:v;}
static PCPanelLayout PCMakePanelLayout(double width,double height,double top,double left,double bottom,double right,double scale){
    PCPanelLayout r={0};r.scale=PCClamp(scale,1,1.35);
    double aw=width-left-right,ah=height-top-bottom;
    if(aw<244||ah<180)return r;
    double w=aw-24;if(w>340)w=340;
    r.header=64*r.scale;
    r.segment=(PCBox){12,4,w-24,38*r.scale};
    r.stats=(PCBox){12,r.segment.y+r.segment.h+12,w-24,156*r.scale};
    r.tips=(PCBox){16,r.stats.y+r.stats.h+12,w-32,104*r.scale};
    r.contact=(PCBox){12,r.tips.y+r.tips.h+12,w-24,156*r.scale};
    r.contentHeight=r.contact.y+r.contact.h+12;
    double h=r.header+r.contentHeight;if(h>ah-24)h=ah-24;
    r.sheet=(PCBox){left+(aw-w)/2,top+(ah-h)/2,w,h};
    r.scroll=(PCBox){0,r.header,w,h-r.header};return r;
}

typedef struct {
    int target,publishing,finished,compatible,status,lastError,nativeError;
    int activeTarget,layoutReady,appliedBps,vbr,useCbr,channels,readback;
    unsigned targetGeneration,appliedGeneration;
    unsigned long long timestamp,now,kbpsMilli;
    int rtt;unsigned long long lossPPM;
} PCPanelInput;
typedef struct {
    char value[32],badge[32],state[64],target[32],mode[64],detail[180];
    int warning,fresh,nativeConfirmed;
} PCPanelText;
static PCPanelText PCMakePanelText(PCPanelInput i){
    PCPanelText o={0};
    int pending=i.targetGeneration!=i.appliedGeneration;
    o.fresh=i.publishing&&i.timestamp&&i.now>=i.timestamp&&i.now-i.timestamp<12000;
    o.nativeConfirmed=i.compatible&&i.publishing&&!pending&&i.target==192&&i.activeTarget==192&&i.layoutReady&&!i.nativeError&&i.appliedBps==192000&&i.vbr==0&&i.useCbr==1&&(i.channels==1||i.channels==2);
    if(o.fresh)snprintf(o.value,sizeof(o.value),"%.1f",i.kbpsMilli/1000.0);
    else snprintf(o.value,sizeof(o.value),"--");
    snprintf(o.badge,sizeof(o.badge),"%s",i.target?"192 CBR":"原版");
    if(i.target)snprintf(o.target,sizeof(o.target),"192 kbps");
    else snprintf(o.target,sizeof(o.target),"跟随原版");
    const char *mode=!i.publishing||pending?"等待生效":!i.target?"跟随原版":o.nativeConfirmed?"Opus · CBR":"CBR 未确认";
    snprintf(o.mode,sizeof(o.mode),"%s",mode);
    if(i.lastError==401||(i.finished&&!i.compatible))snprintf(o.mode,sizeof(o.mode),"未启用");
    const char *state="等待上麦",*detail="上麦后显示实时发送统计";
    if(i.lastError==401){state="旧库冲突";detail="移除旧注入库并重启 TT";o.warning=1;}
    else if(i.finished&&!i.compatible){state="版本不兼容";detail="未启用修改，请使用适配版本";o.warning=1;}
    else if(i.status==6||i.lastError){state="操作异常";detail="请尝试重启 TT，诊断保存在本地";o.warning=1;}
    else if(i.publishing&&i.nativeError&&i.target){state="编码未确认";detail="请尝试恢复原版，诊断保存在本地";o.warning=1;}
    else if(pending&&i.publishing){state="待重新上麦";detail="选择已记住，下麦再上麦后生效";}
    else if(!i.publishing){state="等待上麦";}
    else if(!o.fresh){state="等待统计";detail="暂无新鲜发送统计，不代表连接成功";}
    else if(!i.target){state="原版模式";}
    else if(!o.nativeConfirmed){state="CBR 未确认";detail="已请求 192，等待编码参数确认";o.warning=1;}
    else if(i.kbpsMilli<172800){state="发送波动";detail="实际发送低于目标，请结合听感判断";}
    else {state="发送接近目标";detail="码率来自 SDK，效果以接收端听感为准";}
    snprintf(o.state,sizeof(o.state),"%s",state);
    snprintf(o.detail,sizeof(o.detail),"%s",detail);
    /* Never replace actionable warnings with an attractive numeric status. */
    if(o.fresh&&!o.warning&&!pending){
        if(i.rtt>=0&&i.readback>0)snprintf(o.detail,sizeof(o.detail),"RTT %d ms · 丢包 %.2f%% · SDK %d",i.rtt,i.lossPPM/10000.0,i.readback);
        else snprintf(o.detail,sizeof(o.detail),"码率来自 SDK，效果以接收端听感为准");
    }
    return o;
}
static int PCSavedRate(int exists,int rate){return exists&&(rate==0||rate==192)?rate:192;}
static const char *PCContact(int tag){return tag==1?"monnight1":tag==2?"aze-070130":0;}
#endif
