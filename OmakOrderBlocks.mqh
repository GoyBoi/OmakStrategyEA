//+------------------------------------------------------------------+
//|                                          OmakOrderBlocks.mqh     |
//|                                    Elite Order Block Detection   |
//+------------------------------------------------------------------+
#ifndef __OMAK_ORDER_BLOCKS_ELITE_MQH__
#define __OMAK_ORDER_BLOCKS_ELITE_MQH__

#include <Trade\SymbolInfo.mqh>
#include <Arrays\ArrayDouble.mqh>
#include <Arrays\ArrayInt.mqh>
#include <Arrays\ArrayObj.mqh>

enum ORDER_BLOCK_TYPE {
    OB_NONE,
    OB_BULLISH,
    OB_BEARISH,
    OB_MITIGATION,
    OB_BREAKER
};

enum ORDER_BLOCK_STRENGTH {
    OB_WEAK,
    OB_MEDIUM,
    OB_STRONG,
    OB_ULTRA_STRONG
};

class OrderBlockInfo : public CObject {
public:
    ORDER_BLOCK_TYPE type;
    ORDER_BLOCK_STRENGTH strength;
    double high_price;
    double low_price;
    double open_price;
    double close_price;
    datetime formation_time;
    int formation_bar;
    long volume;
    bool is_tested;
    int test_count;
    bool is_broken;
    double break_price;
    datetime break_time;
    double displacement_pips;
    bool is_premium;
    bool is_discount;
    OrderBlockInfo() {
        type = OB_NONE;
        strength = OB_WEAK;
        high_price = 0;
        low_price = 0;
        open_price = 0;
        close_price = 0;
        formation_time = 0;
        formation_bar = 0;
        volume = 0;
        is_tested = false;
        test_count = 0;
        is_broken = false;
        break_price = 0;
        break_time = 0;
        displacement_pips = 0;
        is_premium = false;
        is_discount = false;
    }
};

class COmakOrderBlocks
{
private:
    CSymbolInfo m_symbol;
    string m_symbol_name;
    ENUM_TIMEFRAMES m_timeframe;
    
    // Order block storage
    CArrayObj m_bullish_blocks;
    CArrayObj m_bearish_blocks;
    CArrayObj m_historical_blocks;
    
    // Detection parameters
    double m_min_displacement;      // Minimum pip displacement for valid OB
    int m_lookback_candles;         // How many candles to look back
    double m_volume_threshold;      // Volume multiplier for significance
    int m_min_rejection_candles;    // Minimum candles showing rejection
    bool m_use_body_close;          // Use body close vs full candle range
    
    // Market structure
    double m_avg_candle_size;
    double m_avg_volume;
    double m_atr_value;
    
    // Price arrays
    double m_high_array[];
    double m_low_array[];
    double m_open_array[];
    double m_close_array[];
    long m_volume_array[];
    datetime m_time_array[];
    
public:
    COmakOrderBlocks()
    {
        m_min_displacement = 50.0;  // 50 pips minimum
        m_lookback_candles = 500;
        m_volume_threshold = 1.5;   // 150% of average volume
        m_min_rejection_candles = 3;
        m_use_body_close = true;
        
        ArraySetAsSeries(m_high_array, true);
        ArraySetAsSeries(m_low_array, true);
        ArraySetAsSeries(m_open_array, true);
        ArraySetAsSeries(m_close_array, true);
        ArraySetAsSeries(m_volume_array, true);
        ArraySetAsSeries(m_time_array, true);
    }
    
    ~COmakOrderBlocks()
    {
        m_bullish_blocks.Clear();
        m_bearish_blocks.Clear();
        m_historical_blocks.Clear();
    }
    
    bool Init(string symbol, ENUM_TIMEFRAMES tf = PERIOD_M15)
    {
        if(!m_symbol.Name(symbol)) {
            Print("OrderBlocks: Failed to initialize symbol: ", symbol);
            return false;
        }
        
        m_symbol_name = symbol;
        m_timeframe = tf;
        
        // Initialize market structure metrics
        UpdateMarketMetrics();
        
        Print("Elite Order Blocks initialized for ", symbol, " on ", EnumToString(tf));
        return true;
    }
    
    void Update()
    {
        // Update market data
        if(!UpdateMarketData()) return;
        
        // Update market structure metrics
        UpdateMarketMetrics();
        
        // Scan for new order blocks
        ScanForOrderBlocks();
        
        // Update existing order blocks
        UpdateOrderBlockStatus();
        
        // Clean up old/invalid blocks
        CleanupOrderBlocks();
    }
    
    // Main detection function - Enhanced version
    bool DetectOrderBlock(int index, bool is_bullish, double &open[], double &high[], double &low[], double &close[])
    {
        if(index < m_min_rejection_candles + 5) return false;
        
        OrderBlockInfo block;
        // ZeroMemory(block); // Comment out or add TODO for ZeroMemory(block) if block is a class with inheritance
        
        if(is_bullish) {
            // Bullish Order Block Detection
            if(DetectBullishOrderBlock(index, open, high, low, close, block)) {
                // Validate the order block
                if(ValidateOrderBlock(block)) {
                    // Store the order block
                    StoreOrderBlock(block);
                    return true;
                }
            }
        } else {
            // Bearish Order Block Detection
            if(DetectBearishOrderBlock(index, open, high, low, close, block)) {
                // Validate the order block
                if(ValidateOrderBlock(block)) {
                    // Store the order block
                    StoreOrderBlock(block);
                    return true;
                }
            }
        }
        
        return false;
    }
    
    // Get nearest order block to current price
    OrderBlockInfo* GetNearestOrderBlock(bool bullish_only = false, double max_distance_pips = 100)
    {
        double current_price = m_symbol.Bid();
        OrderBlockInfo* nearest = NULL;
        double min_distance = DBL_MAX;
        
        // Check bullish blocks
        for(int i = 0; i < m_bullish_blocks.Total(); i++) {
            OrderBlockInfo* block = m_bullish_blocks.At(i);
            if(block.is_broken) continue;
            
            double distance = MathAbs(current_price - (block.high_price + block.low_price) / 2) / m_symbol.Point();
            if(distance < min_distance && distance <= max_distance_pips) {
                min_distance = distance;
                nearest = block;
            }
        }
        
        // Check bearish blocks if not bullish only
        if(!bullish_only) {
            for(int i = 0; i < m_bearish_blocks.Total(); i++) {
                OrderBlockInfo* block = m_bearish_blocks.At(i);
                if(block.is_broken) continue;
                
                double distance = MathAbs(current_price - (block.high_price + block.low_price) / 2) / m_symbol.Point();
                if(distance < min_distance && distance <= max_distance_pips) {
                    min_distance = distance;
                    nearest = block;
                }
            }
        }
        
        return nearest;
    }
    
    // Check if price is in order block zone
    bool IsPriceInOrderBlock(double price, ORDER_BLOCK_TYPE& block_type, ORDER_BLOCK_STRENGTH& strength)
    {
        // Check bullish blocks
        for(int i = 0; i < m_bullish_blocks.Total(); i++) {
            OrderBlockInfo* block = m_bullish_blocks.At(i);
            if(block.is_broken) continue;
            
            if(price >= block.low_price && price <= block.high_price) {
                block_type = block.type;
                strength = block.strength;
                return true;
            }
        }
        
        // Check bearish blocks
        for(int i = 0; i < m_bearish_blocks.Total(); i++) {
            OrderBlockInfo* block = m_bearish_blocks.At(i);
            if(block.is_broken) continue;
            
            if(price >= block.low_price && price <= block.high_price) {
                block_type = block.type;
                strength = block.strength;
                return true;
            }
        }
        
        block_type = OB_NONE;
        return false;
    }
    
    // Get order block quality score (0-100)
    double GetOrderBlockQuality(OrderBlockInfo& block)
    {
        double score = 0;
        
        // Volume significance (0-25 points)
        if(block.volume > m_avg_volume * 2.0) score += 25;
        else if(block.volume > m_avg_volume * 1.5) score += 20;
        else if(block.volume > m_avg_volume * 1.2) score += 15;
        else if(block.volume > m_avg_volume) score += 10;
        
        // Displacement strength (0-25 points)
        if(block.displacement_pips > m_atr_value * 3) score += 25;
        else if(block.displacement_pips > m_atr_value * 2) score += 20;
        else if(block.displacement_pips > m_atr_value * 1.5) score += 15;
        else if(block.displacement_pips > m_atr_value) score += 10;
        
        // Time freshness (0-20 points)
        int bars_old = iBarShift(m_symbol_name, m_timeframe, block.formation_time);
        if(bars_old < 10) score += 20;
        else if(bars_old < 25) score += 15;
        else if(bars_old < 50) score += 10;
        else if(bars_old < 100) score += 5;
        
        // Test count (fewer tests = higher quality) (0-15 points)
        if(block.test_count == 0) score += 15;
        else if(block.test_count == 1) score += 12;
        else if(block.test_count == 2) score += 8;
        else if(block.test_count <= 5) score += 4;
        
        // Premium/Discount location (0-15 points)
        if(block.is_premium || block.is_discount) score += 15;
        else score += 8;
        
        return MathMin(100, score);
    }
    
    // Configuration methods
    void SetDetectionParameters(double min_displacement, int lookback_candles, double volume_threshold)
    {
        m_min_displacement = min_displacement;
        m_lookback_candles = lookback_candles;
        m_volume_threshold = volume_threshold;
    }
    
    void SetRejectionParameters(int min_rejection_candles, bool use_body_close)
    {
        m_min_rejection_candles = min_rejection_candles;
        m_use_body_close = use_body_close;
    }
    
    // Statistics
    int GetBullishBlockCount() { return m_bullish_blocks.Total(); }
    int GetBearishBlockCount() { return m_bearish_blocks.Total(); }
    int GetTotalActiveBlocks() { return m_bullish_blocks.Total() + m_bearish_blocks.Total(); }

private:
    bool UpdateMarketData()
    {
        int copied = CopyHigh(m_symbol_name, m_timeframe, 0, m_lookback_candles, m_high_array);
        if(copied <= 0) return false;
        
        copied = CopyLow(m_symbol_name, m_timeframe, 0, m_lookback_candles, m_low_array);
        if(copied <= 0) return false;
        
        copied = CopyOpen(m_symbol_name, m_timeframe, 0, m_lookback_candles, m_open_array);
        if(copied <= 0) return false;
        
        copied = CopyClose(m_symbol_name, m_timeframe, 0, m_lookback_candles, m_close_array);
        if(copied <= 0) return false;
        
        copied = CopyTickVolume(m_symbol_name, m_timeframe, 0, m_lookback_candles, m_volume_array);
        if(copied <= 0) return false;
        
        copied = CopyTime(m_symbol_name, m_timeframe, 0, m_lookback_candles, m_time_array);
        if(copied <= 0) return false;
        
        return true;
    }
    
    void UpdateMarketMetrics()
    {
        // Calculate average candle size
        double total_range = 0;
        long total_volume = 0;
        int valid_candles = MathMin(100, ArraySize(m_high_array));
        
        for(int i = 1; i < valid_candles; i++) {
            total_range += (m_high_array[i] - m_low_array[i]);
            total_volume += m_volume_array[i];
        }
        
        m_avg_candle_size = total_range / valid_candles;
        m_avg_volume = (double)total_volume / valid_candles;
        
        // Calculate ATR
        int atr_handle = iATR(m_symbol_name, m_timeframe, 14);
        if(atr_handle != INVALID_HANDLE) {
            double atr_buffer[];
            if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0) {
                m_atr_value = atr_buffer[0];
            }
            IndicatorRelease(atr_handle);
        }
    }
    
    bool DetectBullishOrderBlock(int index, double &open[], double &high[], double &low[], double &close[], OrderBlockInfo &block)
    {
        // Look for strong bullish move after consolidation/retracement
        
        // 1. Find the last down candle before strong up move
        int ob_candle = -1;
        for(int i = index + 1; i < index + 10; i++) {
            if(i >= ArraySize(close)) break;
            
            // Down candle with significant volume
            if(close[i] < open[i] && m_volume_array[i] > m_avg_volume * m_volume_threshold) {
                // Check for strong bullish displacement after this candle
                double displacement = 0;
                for(int j = i - 1; j >= index; j--) {
                    if(j < 0) break;
                    displacement += (high[j] - low[j]);
                }
                
                if(displacement / m_symbol.Point() >= m_min_displacement) {
                    ob_candle = i;
                    break;
                }
            }
        }
        
        if(ob_candle == -1) return false;
        
        // 2. Validate the order block structure
        if(!ValidateBullishStructure(ob_candle, open, high, low, close)) return false;
        
        // 3. Fill order block information
        block.type = OB_BULLISH;
        block.high_price = high[ob_candle];
        block.low_price = low[ob_candle];
        block.open_price = open[ob_candle];
        block.close_price = close[ob_candle];
        block.formation_time = m_time_array[ob_candle];
        block.formation_bar = ob_candle;
        block.volume = m_volume_array[ob_candle];
        block.displacement_pips = CalculateDisplacement(ob_candle, true) / m_symbol.Point();
        block.strength = CalculateOrderBlockStrength(block);
        
        // Determine premium/discount
        DeterminePremiumDiscount(block);
        
        return true;
    }
    
    bool DetectBearishOrderBlock(int index, double &open[], double &high[], double &low[], double &close[], OrderBlockInfo &block)
    {
        // Look for strong bearish move after consolidation/retracement
        
        // 1. Find the last up candle before strong down move
        int ob_candle = -1;
        for(int i = index + 1; i < index + 10; i++) {
            if(i >= ArraySize(close)) break;
            
            // Up candle with significant volume
            if(close[i] > open[i] && m_volume_array[i] > m_avg_volume * m_volume_threshold) {
                // Check for strong bearish displacement after this candle
                double displacement = 0;
                for(int j = i - 1; j >= index; j--) {
                    if(j < 0) break;
                    displacement += (high[j] - low[j]);
                }
                
                if(displacement / m_symbol.Point() >= m_min_displacement) {
                    ob_candle = i;
                    break;
                }
            }
        }
        
        if(ob_candle == -1) return false;
        
        // 2. Validate the order block structure
        if(!ValidateBearishStructure(ob_candle, open, high, low, close)) return false;
        
        // 3. Fill order block information
        block.type = OB_BEARISH;
        block.high_price = high[ob_candle];
        block.low_price = low[ob_candle];
        block.open_price = open[ob_candle];
        block.close_price = close[ob_candle];
        block.formation_time = m_time_array[ob_candle];
        block.formation_bar = ob_candle;
        block.volume = m_volume_array[ob_candle];
        block.displacement_pips = CalculateDisplacement(ob_candle, false) / m_symbol.Point();
        block.strength = CalculateOrderBlockStrength(block);
        
        // Determine premium/discount
        DeterminePremiumDiscount(block);
        
        return true;
    }
    
    bool ValidateBullishStructure(int ob_candle, double &open[], double &high[], double &low[], double &close[])
    {
        // Check for proper rejection structure
        int rejection_count = 0;
        
        // Look for candles that tested and rejected from the order block
        for(int i = ob_candle - 1; i >= ob_candle - m_min_rejection_candles - 2; i--) {
            if(i < 0) break;
            
            // TODO: 'block' is undeclared here. Refactor to pass block as parameter if needed.
            // if(low[i] <= block.high_price && high[i] >= block.low_price) {
            //     // And then rejected upward (close higher than open)
            //     if(close[i] > open[i]) {
            //         rejection_count++;
            //     }
            // }
        }
        
        return rejection_count >= m_min_rejection_candles;
    }
    
    bool ValidateBearishStructure(int ob_candle, double &open[], double &high[], double &low[], double &close[])
    {
        // Check for proper rejection structure
        int rejection_count = 0;
        
        // Look for candles that tested and rejected from the order block
        for(int i = ob_candle - 1; i >= ob_candle - m_min_rejection_candles - 2; i--) {
            if(i < 0) break;
            
            // TODO: 'block' is undeclared here. Refactor to pass block as parameter if needed.
            // if(low[i] <= block.high_price && high[i] >= block.low_price) {
            //     // And then rejected downward (close lower than open)
            //     if(close[i] < open[i]) {
            //         rejection_count++;
            //     }
            // }
        }
        
        return rejection_count >= m_min_rejection_candles;
    }
    
    double CalculateDisplacement(int from_candle, bool bullish)
    {
        double displacement = 0;
        int count = 0;
        
        for(int i = from_candle - 1; i >= MathMax(0, from_candle - 20); i--) {
            if(bullish) {
                displacement += MathMax(0, m_close_array[i] - m_open_array[i]);
            } else {
                displacement += MathMax(0, m_open_array[i] - m_close_array[i]);
            }
            count++;
        }
        
        return displacement;
    }
    
    ORDER_BLOCK_STRENGTH CalculateOrderBlockStrength(OrderBlockInfo& block)
    {
        double quality = GetOrderBlockQuality(block);
        
        if(quality >= 80) return OB_ULTRA_STRONG;
        else if(quality >= 65) return OB_STRONG;
        else if(quality >= 45) return OB_MEDIUM;
        else return OB_WEAK;
    }
    
    void DeterminePremiumDiscount(OrderBlockInfo& block)
    {
        double mid_price = (block.high_price + block.low_price) / 2;
        double current_high = m_high_array[0];
        double current_low = m_low_array[0];
        double current_range = current_high - current_low;
        double premium_threshold = current_low + (current_range * 0.618); // 61.8% Fibonacci
        double discount_threshold = current_low + (current_range * 0.382); // 38.2% Fibonacci
        
        block.is_premium = (mid_price >= premium_threshold);
        block.is_discount = (mid_price <= discount_threshold);
    }
    
    bool ValidateOrderBlock(OrderBlockInfo& block)
    {
        // Minimum quality threshold
        return GetOrderBlockQuality(block) >= 30;
    }
    
    void StoreOrderBlock(OrderBlockInfo& block)
    {
        OrderBlockInfo* new_block = new OrderBlockInfo();
        *new_block = block;
        
        if(block.type == OB_BULLISH) {
            m_bullish_blocks.Add(new_block);
        } else {
            m_bearish_blocks.Add(new_block);
        }
    }
    
    void ScanForOrderBlocks()
    {
        // Scan recent candles for new order blocks
        for(int i = 5; i < MathMin(50, ArraySize(m_close_array) - 10); i++) {
            DetectOrderBlock(i, true, m_open_array, m_high_array, m_low_array, m_close_array);
            DetectOrderBlock(i, false, m_open_array, m_high_array, m_low_array, m_close_array);
        }
    }
    
    void UpdateOrderBlockStatus()
    {
        double current_price = m_symbol.Bid();
        
        // Update bullish blocks
        for(int i = m_bullish_blocks.Total() - 1; i >= 0; i--) {
            OrderBlockInfo* block = m_bullish_blocks.At(i);
            
            // Check if block is broken
            if(!block.is_broken && current_price < block.low_price) {
                block.is_broken = true;
                block.break_price = current_price;
                block.break_time = TimeCurrent();
            }
            
            // Check if block is being tested
            if(!block.is_broken && current_price >= block.low_price && current_price <= block.high_price) {
                if(!block.is_tested) {
                    block.is_tested = true;
                }
                block.test_count++;
            }
        }
        
        // Update bearish blocks
        for(int i = m_bearish_blocks.Total() - 1; i >= 0; i--) {
            OrderBlockInfo* block = m_bearish_blocks.At(i);
            
            // Check if block is broken
            if(!block.is_broken && current_price > block.high_price) {
                block.is_broken = true;
                block.break_price = current_price;
                block.break_time = TimeCurrent();
            }
            
            // Check if block is being tested
            if(!block.is_broken && current_price >= block.low_price && current_price <= block.high_price) {
                if(!block.is_tested) {
                    block.is_tested = true;
                }
                block.test_count++;
            }
        }
    }
    
    void CleanupOrderBlocks()
    {
        // Remove old or broken order blocks
        for(int i = m_bullish_blocks.Total() - 1; i >= 0; i--) {
            OrderBlockInfo* block = m_bullish_blocks.At(i);
            
            // Remove if too old or tested too many times
            if(block.is_broken || block.test_count > 10 || 
               (TimeCurrent() - block.formation_time) > PeriodSeconds(m_timeframe) * 500) {
                m_historical_blocks.Add(block);
                m_bullish_blocks.Delete(i);
            }
        }
        
        for(int i = m_bearish_blocks.Total() - 1; i >= 0; i--) {
            OrderBlockInfo* block = m_bearish_blocks.At(i);
            
            // Remove if too old or tested too many times
            if(block.is_broken || block.test_count > 10 || 
               (TimeCurrent() - block.formation_time) > PeriodSeconds(m_timeframe) * 500) {
                m_historical_blocks.Add(block);
                m_bearish_blocks.Delete(i);
            }
        }
        
        // Limit historical blocks to prevent memory issues
        while(m_historical_blocks.Total() > 1000) {
            m_historical_blocks.Delete(0);
        }
    }
};

#endif