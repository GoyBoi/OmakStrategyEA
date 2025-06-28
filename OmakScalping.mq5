
#include "OmakScalpingLib.mqh"
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

int OnInit()
{
    ob.Init(_Symbol);
    ls.Init(_Symbol);
    ama.Init(_Symbol, PERIOD_M15, 21);
    vwap.Init(_Symbol);
    delta.Init(_Symbol);

    Print("OmakScalping EA initialized with all modules.");
    return INIT_SUCCEEDED;
}
