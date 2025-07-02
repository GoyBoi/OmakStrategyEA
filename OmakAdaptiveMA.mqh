#ifndef __OMAK_ADAPTIVE_MA_MQH__
#define __OMAK_ADAPTIVE_MA_MQH__

#include <Trade\SymbolInfo.mqh>

class COmakAdaptiveMA
{
private:
    CSymbolInfo m_adaptive_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_period;
    double m_fastest;
    double m_slowest;
    double m_kama_buffer[1000]; // For up to 1000 bars
    string m_symbol_name;

public:
    COmakAdaptiveMA() { m_period = 10; m_fastest = 2.0/(2+1); m_slowest = 2.0/(30+1); }

    bool Init(string symbol, ENUM_TIMEFRAMES tf, int period)
    {
        if(!m_adaptive_symbol.Name(symbol)) return false;
        m_symbol_name = symbol;
        m_timeframe = tf;
        m_period = period;
        ArrayInitialize(m_kama_buffer, 0);
        return true;
    }

    // Calculate KAMA for the current bar (shift=0)
    double GetAdaptiveMA(int shift = 0)
    {
        int bars = MathMin(1000, Bars(m_symbol_name, m_timeframe));
        if(bars <= m_period+2) return 0;
        double price[1000];
        if(CopyClose(m_symbol_name, m_timeframe, 0, bars, price) <= m_period+2) return 0;
        // Calculate KAMA for all bars up to shift
        for(int i=bars-1; i>=shift; i--)
        {
            if(i == bars-1) {
                m_kama_buffer[i] = price[i];
                continue;
            }
            if(i-m_period < 0) {
                m_kama_buffer[i] = price[i]; // Not enough history, fallback
                continue;
            }
            double change = MathAbs(price[i] - price[i-m_period]);
            double volatility = 0;
            bool valid = true;
            for(int j=0; j<m_period; j++) {
                if(i-j-1 < 0) { valid = false; break; }
                volatility += MathAbs(price[i-j] - price[i-j-1]);
            }
            if(!valid || volatility == 0) {
                m_kama_buffer[i] = price[i];
                continue;
            }
            double er = change / volatility;
            double sc = MathPow(er * (m_fastest - m_slowest) + m_slowest, 2);
            m_kama_buffer[i] = m_kama_buffer[i+1] + sc * (price[i] - m_kama_buffer[i+1]);
        }
        return m_kama_buffer[shift];
    }
};

#endif
