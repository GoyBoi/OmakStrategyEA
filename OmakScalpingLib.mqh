
#include "OmakOrderBlocks.mqh"
#include "OmakLiquiditySweeps.mqh"
#include "OmakAdaptiveMA.mqh"
#include "OmakVWAP.mqh"
#include "OmakVolumeDelta.mqh"

COmakOrderBlocks ob;
COmakLiquiditySweeps ls;
COmakAdaptiveMA ama;
COmakVWAP vwap;
COmakVolumeDelta delta;

bool CheckFullConfluence(int index, double high[], double low[], double open[], double close[])
{
    if(!ob.Init(_Symbol)) return false;
    if(!ls.Init(_Symbol)) return false;
    if(!ama.Init(_Symbol, PERIOD_M15, 21)) return false;

    return (ob.DetectOrderBlock(index, true, open, high, low, close) &&
            ls.IsLiquiditySweep(index, high, low, open, close) &&
            ama.GetAdaptiveMA(0) > ama.GetAdaptiveMA(1));
}
