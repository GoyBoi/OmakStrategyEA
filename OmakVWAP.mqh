
#ifndef __OMAK_VWAP_MQH__
#define __OMAK_VWAP_MQH__

#include <Trade\SymbolInfo.mqh>

class COmakVWAP
{
private:
    CSymbolInfo m_symbol;
    double m_cum_price_vol, m_cum_volume;

public:
    COmakVWAP() { m_cum_price_vol = m_cum_volume = 0; }

    bool Init(string symbol) { return m_symbol.Name(symbol); }

    void Reset() { m_cum_price_vol = m_cum_volume = 0; }

    void Update(double price, double volume)
    {
        m_cum_price_vol += price * volume;
        m_cum_volume += volume;
    }

    double GetVWAP() { return (m_cum_volume != 0) ? (m_cum_price_vol / m_cum_volume) : 0; }
};

#endif
