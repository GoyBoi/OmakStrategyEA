
#ifndef __OMAK_ADAPTIVE_MA_MQH__
#define __OMAK_ADAPTIVE_MA_MQH__

#include <Trade\SymbolInfo.mqh>

class COmakAdaptiveMA
{
private:
    CSymbolInfo m_symbol;
    int m_ma_handle;

public:
    COmakAdaptiveMA() { m_ma_handle = INVALID_HANDLE; }

    bool Init(string symbol, ENUM_TIMEFRAMES tf, int period)
    {
        if(!m_symbol.Name(symbol)) return false;
        m_ma_handle = iMA(symbol, tf, period, 0, MODE_LWMA, PRICE_CLOSE);
        return (m_ma_handle != INVALID_HANDLE);
    }

    double GetAdaptiveMA(int shift = 0)
    {
        double buffer[];
        if(CopyBuffer(m_ma_handle, 0, shift, 1, buffer) > 0)
            return buffer[0];
        return 0;
    }
};

#endif
