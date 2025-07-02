#ifndef __OMAK_VOLUME_DELTA_MQH__
#define __OMAK_VOLUME_DELTA_MQH__

#include <Trade\SymbolInfo.mqh>

class COmakVolumeDelta
{
private:
    CSymbolInfo m_delta_symbol;
    string m_symbol_name;
    ENUM_TIMEFRAMES m_timeframe;
    double m_bar_delta[1000]; // Bar-wise delta
    double m_cvd[1000];       // Cumulative volume delta

public:
    COmakVolumeDelta() { ArrayInitialize(m_bar_delta, 0); ArrayInitialize(m_cvd, 0); }

    bool Init(string symbol, ENUM_TIMEFRAMES tf = PERIOD_M1)
    {
        if(!m_delta_symbol.Name(symbol)) return false;
        m_symbol_name = symbol;
        m_timeframe = tf;
        return true;
    }

    // Update volume delta for the last N bars
    void Update(int bars = 100)
    {
        int total = MathMin(bars, 1000);
        long tick_vol[1000];
        double close[1000];
        if(CopyTickVolume(m_symbol_name, m_timeframe, 0, total, tick_vol) <= 0) return;
        if(CopyClose(m_symbol_name, m_timeframe, 0, total, close) <= 0) return;
        for(int i=total-1; i>=1; i--)
        {
            // Approximate: up-tick = buy, down-tick = sell
            double buy = 0, sell = 0;
            if(close[i] > close[i+1]) buy = (double)tick_vol[i];
            else if(close[i] < close[i+1]) sell = (double)tick_vol[i];
            // If unchanged, ignore
            m_bar_delta[i] = buy - sell;
            m_cvd[i] = (i < total-1 ? m_cvd[i+1] : 0) + m_bar_delta[i];
        }
    }

    // Get bar-wise delta (0 = current bar)
    double GetBarDelta(int shift = 0) { return m_bar_delta[shift]; }
    // Get cumulative volume delta (0 = current bar)
    double GetCVD(int shift = 0) { return m_cvd[shift]; }
};

#endif
