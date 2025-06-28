
#ifndef __OMAK_VOLUME_DELTA_MQH__
#define __OMAK_VOLUME_DELTA_MQH__

#include <Trade\SymbolInfo.mqh>

class COmakVolumeDelta
{
private:
    CSymbolInfo m_symbol;
    double m_cvd;

public:
    COmakVolumeDelta() { m_cvd = 0; }

    bool Init(string symbol) { return m_symbol.Name(symbol); }

    void Update(double buy_vol, double sell_vol) { m_cvd += (buy_vol - sell_vol); }

    double GetCVD() { return m_cvd; }
};

#endif
