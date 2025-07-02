//+------------------------------------------------------------------+
//|                                               OmakVWAP.mqh       |
//|                                    Elite VWAP with Session Logic |
//+------------------------------------------------------------------+
#ifndef __OMAK_VWAP_ELITE_MQH__
#define __OMAK_VWAP_ELITE_MQH__

#include <Trade\SymbolInfo.mqh>

enum VWAP_SESSION_TYPE {
    VWAP_DAILY,
    VWAP_WEEKLY, 
    VWAP_MONTHLY,
    VWAP_LONDON,
    VWAP_NY,
    VWAP_ASIAN
};

class COmakVWAP
{
private:
    CSymbolInfo m_vwap_symbol;
    string m_symbol_name;
    ENUM_TIMEFRAMES m_timeframe;
    VWAP_SESSION_TYPE m_session_type;
    
    // VWAP calculation variables
    double m_cum_price_vol;
    double m_cum_volume;
    datetime m_session_start;
    datetime m_last_reset;
    
    // Enhanced VWAP bands
    double m_vwap_value;
    double m_vwap_upper_1;
    double m_vwap_upper_2;
    double m_vwap_lower_1;
    double m_vwap_lower_2;
    
    // Session management
    bool m_auto_reset;
    int m_lookback_bars;
    
    // Volume analysis
    double m_avg_volume;
    double m_volume_threshold;
    bool m_use_volume_filter;
    
    // Price arrays for calculations
    double m_price_array[];
    double m_volume_array[];
    long m_tick_volume_array[];
    datetime m_time_array[];
    
public:
    COmakVWAP() 
    { 
        m_cum_price_vol = 0;
        m_cum_volume = 0;
        m_session_start = 0;
        m_last_reset = 0;
        m_vwap_value = 0;
        m_auto_reset = true;
        m_lookback_bars = 200;
        m_session_type = VWAP_DAILY;
        m_use_volume_filter = true;
        m_volume_threshold = 1.5; // 150% of average volume
        
        ArraySetAsSeries(m_price_array, true);
        ArraySetAsSeries(m_volume_array, true);
        ArraySetAsSeries(m_tick_volume_array, true);
        ArraySetAsSeries(m_time_array, true);
    }
    
    bool Init(string symbol, ENUM_TIMEFRAMES tf = PERIOD_M15, VWAP_SESSION_TYPE session = VWAP_DAILY)
    {
        if(!m_vwap_symbol.Name(symbol)) {
            Print("VWAP: Failed to initialize symbol: ", symbol);
            return false;
        }
        
        m_symbol_name = symbol;
        m_timeframe = tf;
        m_session_type = session;
        
        // Initialize session
        ResetSession();
        
        Print("Elite VWAP initialized for ", symbol, " on ", EnumToString(tf));
        return true;
    }
    
    void Update()
    {
        // Check if session reset is needed
        if(m_auto_reset && ShouldResetSession()) {
            ResetSession();
        }
        
        // Get current market data
        if(!UpdateMarketData()) return;
        
        // Calculate VWAP and bands
        CalculateVWAP();
        CalculateVWAPBands();
        
        // Update volume analysis
        UpdateVolumeAnalysis();
    }
    
    // Main VWAP value
    double GetVWAP() { return m_vwap_value; }
    
    // VWAP bands for support/resistance
    double GetUpperBand1() { return m_vwap_upper_1; }
    double GetUpperBand2() { return m_vwap_upper_2; }
    double GetLowerBand1() { return m_vwap_lower_1; }
    double GetLowerBand2() { return m_vwap_lower_2; }
    
    // Price relative to VWAP
    double GetVWAPDistance(double price = 0) 
    { 
        if(price == 0) price = m_vwap_symbol.Bid();
        if(m_vwap_value == 0) return 0;
        return (price - m_vwap_value) / m_vwap_value * 100; 
    }
    
    // Volume analysis
    bool IsVolumeSignificant() 
    { 
        return !m_use_volume_filter || (GetCurrentVolume() > m_avg_volume * m_volume_threshold); 
    }
    
    double GetVolumeRatio() 
    { 
        return (m_avg_volume > 0) ? GetCurrentVolume() / m_avg_volume : 1.0; 
    }
    
    // VWAP trading signals
    bool IsBullishSignal(double price = 0)
    {
        if(price == 0) price = m_vwap_symbol.Bid();
        return (price > m_vwap_value && IsVolumeSignificant());
    }
    
    bool IsBearishSignal(double price = 0)
    {
        if(price == 0) price = m_vwap_symbol.Bid();
        return (price < m_vwap_value && IsVolumeSignificant());
    }
    
    // Support/Resistance levels
    bool IsNearSupport(double price = 0, double tolerance = 0.1)
    {
        if(price == 0) price = m_vwap_symbol.Bid();
        double distance = MathAbs(price - m_vwap_lower_1) / m_vwap_symbol.Point();
        return distance <= tolerance * 100; // Convert to points
    }
    
    bool IsNearResistance(double price = 0, double tolerance = 0.1)
    {
        if(price == 0) price = m_vwap_symbol.Bid();
        double distance = MathAbs(price - m_vwap_upper_1) / m_vwap_symbol.Point();
        return distance <= tolerance * 100; // Convert to points
    }
    
    // Manual reset
    void ResetSession()
    {
        m_cum_price_vol = 0;
        m_cum_volume = 0;
        m_session_start = TimeCurrent();
        m_last_reset = TimeCurrent();
        m_vwap_value = 0;
        
        // Clear arrays
        ArrayFree(m_price_array);
        ArrayFree(m_volume_array);
        ArrayFree(m_tick_volume_array);
        ArrayFree(m_time_array);
    }
    
    // Configuration
    void SetSessionType(VWAP_SESSION_TYPE type) { m_session_type = type; }
    void SetAutoReset(bool auto_reset) { m_auto_reset = auto_reset; }
    void SetLookbackBars(int bars) { m_lookback_bars = MathMax(50, bars); }
    void SetVolumeFilter(bool use_filter, double threshold = 1.5) 
    { 
        m_use_volume_filter = use_filter;
        m_volume_threshold = threshold;
    }
    
private:
    bool ShouldResetSession()
    {
        MqlDateTime current_time, vwap_last_reset_time;
        TimeToStruct(TimeCurrent(), current_time);
        TimeToStruct(m_last_reset, vwap_last_reset_time);
        
        switch(m_session_type) {
            case VWAP_DAILY:
                return (current_time.day != vwap_last_reset_time.day);
                
            case VWAP_WEEKLY:
                return (current_time.day_of_week == 1 && vwap_last_reset_time.day_of_week != 1);
                
            case VWAP_MONTHLY:
                return (current_time.mon != vwap_last_reset_time.mon);
                
            case VWAP_LONDON:
                return (current_time.hour == 8 && vwap_last_reset_time.hour != 8);
                
            case VWAP_NY:
                return (current_time.hour == 13 && vwap_last_reset_time.hour != 13);
                
            case VWAP_ASIAN:
                return (current_time.hour == 0 && vwap_last_reset_time.hour != 0);
        }
        
        return false;
    }
    
    bool UpdateMarketData()
    {
        // Copy price data
        if(CopyHigh(m_symbol_name, m_timeframe, 0, m_lookback_bars, m_price_array) <= 0) return false;
        if(CopyLow(m_symbol_name, m_timeframe, 0, m_lookback_bars, m_volume_array) <= 0) return false;
        if(CopyTickVolume(m_symbol_name, m_timeframe, 0, m_lookback_bars, m_tick_volume_array) <= 0) return false;
        if(CopyTime(m_symbol_name, m_timeframe, 0, m_lookback_bars, m_time_array) <= 0) return false;
        
        return true;
    }
    
    void CalculateVWAP()
{
    double total_price_volume = 0;
    double total_volume = 0;

    for(int i = ArraySize(m_tick_volume_array) - 1; i >= 0; i--)
    {
        // Skip if session start time constraint
        if(m_time_array[i] < m_session_start) continue;

        // Use typical price for calculation
        double high = iHigh(m_symbol_name, m_timeframe, i);
        double low = iLow(m_symbol_name, m_timeframe, i);
        double close = iClose(m_symbol_name, m_timeframe, i);
        double typical_price = (high + low + close) / 3.0;

        double volume = (double)m_tick_volume_array[i];

        total_price_volume += typical_price * volume;
        total_volume += volume;
    }

    if(total_volume > 0) 
    {
        m_vwap_value = total_price_volume / total_volume;

        // Update session start for next calculation
        m_session_start = m_time_array[ArraySize(m_time_array)-1];
    }
}
    
    void CalculateVWAPBands()
{
    if(m_vwap_value == 0) return;

    CArrayDouble *deviations = new CArrayDouble();
    CArrayDouble *weights = new CArrayDouble();

    for(int i = ArraySize(m_tick_volume_array) - 1; i >= 0; i--)
    {
        if(m_time_array[i] < m_session_start) continue;

        double high = iHigh(m_symbol_name, m_timeframe, i);
        double low = iLow(m_symbol_name, m_timeframe, i);
        double close = iClose(m_symbol_name, m_timeframe, i);
        double typical_price = (high + low + close) / 3.0;

        double diff = typical_price - m_vwap_value;
        deviations.Add(MathAbs(diff));
        weights.Add((double)m_tick_volume_array[i]);
    }

    // Weighted median absolute deviation
    double mad = CalculateWeightedMAD(deviations, weights);

    // Create bands at 1 and 2 MADs
    m_vwap_upper_1 = m_vwap_value + mad;
    m_vwap_upper_2 = m_vwap_value + (mad * 2);
    m_vwap_lower_1 = m_vwap_value - mad;
    m_vwap_lower_2 = m_vwap_value - (mad * 2);

    delete deviations;
    delete weights;
}

double CalculateWeightedMAD(CArrayDouble *deviations, CArrayDouble *weights)
{
    // Sort deviations by value
    // TODO: Implement SortIndices or provide alternative
    // CArrayInt indices = SortIndices(deviations);

    // Calculate cumulative weight
    double total_weight = 0;
    for(int i=0; i<weights.Total(); i++)
        total_weight += weights.At(i);

    // Find weighted median index
    double cum_weight = 0;
    int median_idx = 0;
    /*
    for(int i=0; i<indices.Total(); i++)
    {
        cum_weight += weights.At(indices[i]);
        if(cum_weight >= total_weight / 2)
        {
            median_idx = indices[i];
            break;
        }
    }
    */

    // Return median absolute deviation
    return deviations.At(median_idx);
}
    
    void UpdateVolumeAnalysis()
    {
        // Calculate average volume
        double total_volume = 0;
        int valid_bars = 0;
        
        for(int i = 0; i < MathMin(50, ArraySize(m_tick_volume_array)); i++) {
            total_volume += (double)m_tick_volume_array[i];
            valid_bars++;
        }
        
        if(valid_bars > 0) {
            m_avg_volume = total_volume / valid_bars;
        }
    }
    
    double GetCurrentVolume()
    {
        if(ArraySize(m_tick_volume_array) > 0) {
            return (double)m_tick_volume_array[0];
        }
        return 0;
    }
};

#endif
