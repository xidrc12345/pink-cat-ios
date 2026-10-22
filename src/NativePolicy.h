#ifndef PC_NATIVE_POLICY_H
#define PC_NATIVE_POLICY_H
static int PCBootstrapRate(int rate){return rate>192?192:rate;}
static int PCRequestedChannels(int rate,int original){(void)rate;return original;}
static int PCNativeRateValid(int rate,int channels){return rate==192&&(channels==1||channels==2)&&rate*1000<=300000*channels;}
static int PCNativeMayApply(int target,int sourceRate,int userRate){
    if(target<=0||sourceRate!=target*1000)return 0;
    /* Change pacing only after the host has actually configured 192k. */
    return userRate==target*1000;
}
static int PCNativeShapeValid(int fs,int ch,int actual,int samples,int pcm,int application){
    return fs==48000&&(ch==1||ch==2)&&actual==ch&&(samples==480||samples==960)&&pcm==samples*ch*2&&application==2049;
}
#endif
