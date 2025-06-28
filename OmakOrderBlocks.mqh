
#ifndef __OMAK_ORDER_BLOCKS_MQH__
#define __OMAK_ORDER_BLOCKS_MQH__

#include <Trade\SymbolInfo.mqh>

class COmakOrderBlocks
{
private:
    CSymbolInfo m_symbol;

public:
    COmakOrderBlocks() {}

    bool Init(string symbol) { return m_symbol.Name(symbol); }

    bool DetectOrderBlock(int index, bool is_bullish, double open[], double high[], double low[], double close[])
    {
        if(index < 2) return false;
        double prev_high = high[index + 1];
        double prev_low = low[index + 1];
        double prev_close = close[index + 1];

        if(is_bullish && prev_close < prev_low && close[index] > prev_high)
            return true;
        if(!is_bullish && prev_close > prev_high && close[index] < prev_low)
            return true;

        return false;
    }
};

#endif
