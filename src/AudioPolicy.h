#ifndef PC_AUDIO_POLICY_H
#define PC_AUDIO_POLICY_H
static const int PCRates[]={0,192};
#define PC_RATE_COUNT ((int)(sizeof(PCRates)/sizeof(PCRates[0])))
static int PCRateAllowed(int rate){for(int i=0;i<PC_RATE_COUNT;i++)if(PCRates[i]==rate)return 1;return 0;}
static int PCMetricValid(double value,double ceiling){return value==value&&value>=0&&value<=ceiling;}
static double PCByteRate(double bytes,double prior,double milliseconds){
    if(!PCMetricValid(bytes,1e15)||!PCMetricValid(prior,1e15)||bytes<prior||!PCMetricValid(milliseconds,30000)||milliseconds<100)return -1;
    return (bytes-prior)*8.0/milliseconds;
}
#endif
