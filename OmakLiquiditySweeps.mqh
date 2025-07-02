//+------------------------------------------------------------------+
//|                                      OmakLiquiditySweeps.mqh     |
//|                                Elite Liquidity Sweep Detection   |
//+------------------------------------------------------------------+
#ifndef __OMAK_LIQUIDITY_SWEEPS_ELITE_MQH__
#define __OMAK_LIQUIDITY_SWEEPS_ELITE_MQH__

#include <Trade\SymbolInfo.mqh>
#include <Arrays\ArrayDouble.mqh>
#include <Arrays\ArrayInt.mqh>
#include <Arrays\ArrayObj.mqh>

enum LIQUIDITY_TYPE {
    LIQ_NONE,
    LIQ_BUY_SIDE,          // Above highs
    LIQ_SELL_SIDE,         // Below lows  
    LIQ_EQUAL_HIGHS,       // Double/triple tops
    LIQ_EQUAL_LOWS,        // Double/triple bottoms
    LIQ_RELATIVE_HIGH,     // Local high liquidity
    LIQ_RELATIVE_LOW       // Local low liquidity
};

enum SWEEP_STRENGTH {
    SWEEP_WEAK,
    SWEEP_MEDIUM,
    SWEEP_STRONG,
    SWEEP_ULTRA_STRONG
};

class LiquidityPool : public CObject {
public:
    LIQUIDITY_TYPE type;
    SWEEP_STRENGTH strength;
    double price_level;
    datetime formation_time;
    int formation_bar;
    bool is_swept;
    datetime sweep_time;
    double volume_at_formation;
    double rejection_strength;
    int touch_count;
    double distance_to_structure;
    bool is_external;
    double expected_target;
    LiquidityPool() {
        type = LIQ_NONE;
        strength = SWEEP_WEAK;
        price_level = 0;
        formation_time = 0;
        formation_bar = 0;
        is_swept = false;
        sweep_time = 0;
        volume_at_formation = 0;
        rejection_strength = 0;
        touch_count = 0;
        distance_to_structure = 0;
        is_external = false;
        expected_target = 0;
    }
};

class SweepEvent : public CObject {
public:
    LIQUIDITY_TYPE liquidity_type;
    SWEEP_STRENGTH strength;
    double sweep_price;
    datetime sweep_time;
    int sweep_bar;
    double volume_on_sweep;
    double displacement_after;
    bool failed_sweep;
    double reversal_strength;
    SweepEvent() {
        liquidity_type = LIQ_NONE;
        strength = SWEEP_WEAK;
        sweep_price = 0;
        sweep_time = 0;
        sweep_bar = 0;
        volume_on_sweep = 0;
        displacement_after = 0;
        failed_sweep = false;
        reversal_strength = 0;
    }
};

class COmakLiquiditySweeps
{
private:
    CSymbolInfo m_symbol;
    string m_symbol_name;
    ENUM_TIMEFRAMES m_timeframe;
    
    // Liquidity pools storage
    CArrayObj m_liquidity_pools;
    CArrayObj m_sweep_history;
    
    // Detection parameters
    double m_min_wick_ratio;           // Minimum wick size vs body
    double m_equal_level_tolerance;    // Tolerance for equal highs/lows
    int m_lookback_periods;            // Periods to look back for liquidity
    double m_volume_threshold;         // Volume significance threshold
    int m_min_touches;                 // Minimum touches for liquidity pool
    double m_displacement_threshold;   // Minimum displacement after sweep
    
    // Market structure data
    double m_avg_candle_range;
    double m_avg_volume;
    double m_atr_value;
    
    // Price arrays
    double m_high_array[];
    double m_low_array[];
    double m_open_array[];
    double m_close_array[];
    long m_volume_array[];
    datetime m_time_array[];
    
    // Fractal/swing point arrays
    CArrayDouble m_swing_highs;
    CArrayDouble m_swing_lows;
    CArrayInt m_swing_high_bars;
    CArrayInt m_swing_low_bars;

public:
    COmakLiquiditySweeps()
    {
        m_min_wick_ratio = 0.3;        // 30% minimum wick size
        m_equal_level_tolerance = 20;   // 20 points tolerance
        m_lookback_periods = 200;
        m_volume_threshold = 1.2;       // 120% of average volume
        m_min_touches = 2;              // Minimum 2 touches for pool
        m_displacement_threshold = 0.5; // 0.5 ATR by default
        ArraySetAsSeries(m_high_array, true);
        ArraySetAsSeries(m_low_array, true);
        ArraySetAsSeries(m_open_array, true);
        ArraySetAsSeries(m_close_array, true);
        ArraySetAsSeries(m_volume_array, true);
        ArraySetAsSeries(m_time_array, true);
    }

    bool Init(string symbol, ENUM_TIMEFRAMES tf = PERIOD_M15)
    {
        if(!m_symbol.Name(symbol)) return false;
        m_symbol_name = symbol;
        m_timeframe = tf;
        UpdateMarketMetrics();
        return true;
    }

    void Update()
    {
        if(!UpdateMarketData()) return;
        UpdateMarketMetrics();
        ScanForLiquidityPools();
        DetectLiquiditySweeps();
        CleanupPools();
    }

    // Main detection: returns true if a sweep is detected at index
    bool IsLiquiditySweep(int index, double &high[], double &low[], double &open[], double &close[])
    {
        // Check for buy-side sweep (above previous highs)
        if(IsBuySideSweep(index, high, low, open, close)) return true;
        // Check for sell-side sweep (below previous lows)
        if(IsSellSideSweep(index, high, low, open, close)) return true;
        return false;
    }

private:
    bool UpdateMarketData()
    {
        int copied = CopyHigh(m_symbol_name, m_timeframe, 0, m_lookback_periods, m_high_array);
        if(copied <= 0) return false;
        copied = CopyLow(m_symbol_name, m_timeframe, 0, m_lookback_periods, m_low_array);
        if(copied <= 0) return false;
        copied = CopyOpen(m_symbol_name, m_timeframe, 0, m_lookback_periods, m_open_array);
        if(copied <= 0) return false;
        copied = CopyClose(m_symbol_name, m_timeframe, 0, m_lookback_periods, m_close_array);
        if(copied <= 0) return false;
        copied = CopyTickVolume(m_symbol_name, m_timeframe, 0, m_lookback_periods, m_volume_array);
        if(copied <= 0) return false;
        copied = CopyTime(m_symbol_name, m_timeframe, 0, m_lookback_periods, m_time_array);
        if(copied <= 0) return false;
        return true;
    }

    void UpdateMarketMetrics()
    {
        double total_range = 0;
        long total_volume = 0;
        int valid = MathMin(100, ArraySize(m_high_array));
        for(int i=1; i<valid; i++) {
            total_range += (m_high_array[i] - m_low_array[i]);
            total_volume += m_volume_array[i];
        }
        m_avg_candle_range = total_range / valid;
        m_avg_volume = (double)total_volume / valid;
        int atr_handle = iATR(m_symbol_name, m_timeframe, 14);
        if(atr_handle != INVALID_HANDLE) {
            double atr_buf[];
            if(CopyBuffer(atr_handle, 0, 0, 1, atr_buf) > 0) m_atr_value = atr_buf[0];
            IndicatorRelease(atr_handle);
        }
    }

    void ScanForLiquidityPools()
    {
        // Find equal highs/lows (liquidity pools)
        for(int i=10; i<m_lookback_periods-10; i++) {
            // Equal highs
            if(MathAbs(m_high_array[i] - m_high_array[i-1]) <= m_equal_level_tolerance * m_symbol.Point()) {
                AddLiquidityPool(LIQ_EQUAL_HIGHS, m_high_array[i], i);
            }
            // Equal lows
            if(MathAbs(m_low_array[i] - m_low_array[i-1]) <= m_equal_level_tolerance * m_symbol.Point()) {
                AddLiquidityPool(LIQ_EQUAL_LOWS, m_low_array[i], i);
            }
        }
    }

    void AddLiquidityPool(LIQUIDITY_TYPE type, double price, int bar)
    {
        LiquidityPool* pool = new LiquidityPool();
        pool.type = type;
        pool.price_level = price;
        pool.formation_time = (datetime)m_time_array[bar]; // explicit cast for safety
        pool.formation_bar = bar;
        pool.is_swept = false;
        pool.volume_at_formation = (double)m_volume_array[bar]; // explicit cast for safety
        pool.touch_count = 1;
        pool.strength = SWEEP_WEAK;
        pool.distance_to_structure = 0;
        pool.is_external = false;
        pool.expected_target = 0;
        m_liquidity_pools.Add(pool);
    }

    void DetectLiquiditySweeps()
    {
        // Look for sweeps above highs (buy-side) and below lows (sell-side)
        for(int i=2; i<m_lookback_periods-2; i++) {
            if(IsBuySideSweep(i, m_high_array, m_low_array, m_open_array, m_close_array)) {
                RegisterSweepEvent(LIQ_BUY_SIDE, m_high_array[i], i);
            }
            if(IsSellSideSweep(i, m_high_array, m_low_array, m_open_array, m_close_array)) {
                RegisterSweepEvent(LIQ_SELL_SIDE, m_low_array[i], i);
            }
        }
    }

    bool IsBuySideSweep(int i, double &high[], double &low[], double &open[], double &close[])
    {
        // Wick above previous highs, closes back below, with volume
        if(i<2) return false;
        double prev_high = high[i-1];
        double wick = high[i] - MathMax(open[i], close[i]);
        double body = MathAbs(open[i] - close[i]);
        if(high[i] > prev_high && wick > body * m_min_wick_ratio && m_volume_array[i] > m_avg_volume * m_volume_threshold) {
            // Displacement confirmation
            if((high[i] - low[i]) > m_atr_value * m_displacement_threshold) return true;
        }
        return false;
    }

    bool IsSellSideSweep(int i, double &high[], double &low[], double &open[], double &close[])
    {
        // Wick below previous lows, closes back above, with volume
        if(i<2) return false;
        double prev_low = low[i-1];
        double wick = MathMin(open[i], close[i]) - low[i];
        double body = MathAbs(open[i] - close[i]);
        if(low[i] < prev_low && wick > body * m_min_wick_ratio && m_volume_array[i] > m_avg_volume * m_volume_threshold) {
            if((high[i] - low[i]) > m_atr_value * m_displacement_threshold) return true;
        }
        return false;
    }

    void RegisterSweepEvent(LIQUIDITY_TYPE type, double price, int bar)
    {
        SweepEvent* evt = new SweepEvent();
        evt.liquidity_type = type;
        evt.sweep_price = price;
        evt.sweep_time = (datetime)m_time_array[bar]; // explicit cast for safety
        evt.sweep_bar = bar;
        evt.volume_on_sweep = (double)m_volume_array[bar]; // explicit cast for safety
        evt.strength = SWEEP_MEDIUM;
        evt.displacement_after = m_high_array[bar] - m_low_array[bar];
        evt.failed_sweep = false;
        evt.reversal_strength = 0;
        m_sweep_history.Add(evt);
    }

    void CleanupPools()
    {
        // Remove old pools and sweeps
        while(m_liquidity_pools.Total() > 200) m_liquidity_pools.Delete(0);
        while(m_sweep_history.Total() > 200) m_sweep_history.Delete(0);
    }

};

#endif
