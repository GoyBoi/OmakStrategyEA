
#ifndef __OMAK_LIQUIDITY_SWEEPS_MQH__
#define __OMAK_LIQUIDITY_SWEEPS_MQH__

#include <Trade\SymbolInfo.mqh>

class COmakLiquiditySweeps
{
private:
    CSymbolInfo m_symbol;
    double m_wick_threshold;

public:
    COmakLiquiditySweeps() { m_wick_threshold = 0.2; }

    bool Init(string symbol) { return m_symbol.Name(symbol); }

    bool IsLiquiditySweep(int index, double high[], double low[], double open[], double close[])
    {
        if(index < 0) return false;
        double range = high[index] - low[index];
        double body = MathAbs(close[index] - open[index]);
        double upper_wick = high[index] - MathMax(open[index], close[index]);
        double lower_wick = MathMin(open[index], close[index]) - low[index];

        return (upper_wick > range * m_wick_threshold) || (lower_wick > range * m_wick_threshold);
    }
};

#endif
