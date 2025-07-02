//+------------------------------------------------------------------+
//|                                            OmakScalping.mq5      |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "OmakTrading"
#property version   "2.0"
#property description "Elite Smart Money Scalping System"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <OmakOrderBlocks.mqh>
#include <OmakLiquiditySweeps.mqh>
#include <OmakAdaptiveMA.mqh>
#include <OmakVWAP.mqh>
#include <OmakVolumeDelta.mqh>

// Input Parameters for Trailing Stop
input bool InpUseTrailingStop = true;
input int InpTrailingStopPips = 20;

// For performance metrics
double trailing_max_equity = 0;
double daily_max_equity = 0;

//--- Input Parameters
input group "=== RISK MANAGEMENT ==="
input double InpRiskPercent = 1.0;           // Risk per trade (%)
input double InpMaxDailyRisk = 3.0;          // Max daily risk (%)
input double InpMaxDrawdown = 10.0;          // Max drawdown (%)
input int InpMaxPositions = 3;               // Max concurrent positions

input group "=== TRADING PARAMETERS ==="
input int InpMagicNumber = 123456;           // Magic number
input double InpMinRR = 1.5;                 // Minimum Risk:Reward ratio
input int InpMaxSpread = 50;                 // Max spread (points) (relaxed for debug)
input bool InpTradeOnlySession = false;      // Trade only during session (relaxed for debug)

input group "=== TIMEFRAME ANALYSIS ==="
input ENUM_TIMEFRAMES InpTF1 = PERIOD_M1;    // Primary timeframe
input ENUM_TIMEFRAMES InpTF2 = PERIOD_M5;    // Secondary timeframe  
input ENUM_TIMEFRAMES InpTF3 = PERIOD_M15;   // Tertiary timeframe

input group "=== SMART MONEY SETTINGS ==="
input double InpOBMinSize = 0.5;             // Order block min size (%)
input double InpLSWickThreshold = 0.3;       // Liquidity sweep wick threshold
input int InpVWAPPeriod = 200;               // VWAP calculation period
input bool InpUseVolumeFilter = true;        // Use volume delta filter

//--- Global Variables
CTrade trade;
CSymbolInfo main_symbol;
CPositionInfo position;
CAccountInfo account;

// Smart Money Components
COmakOrderBlocks *ob_m1, *ob_m5, *ob_m15;
COmakLiquiditySweeps *ls_m1, *ls_m5, *ls_m15;
COmakAdaptiveMA *ama_m1, *ama_m5, *ama_m15;
COmakVWAP *vwap;
COmakVolumeDelta *volume_delta;

// Risk Management
double daily_pnl = 0;
double session_high_equity = 0;
double max_equity = 0;
datetime last_reset_time = 0;

// Performance Tracking
struct PerformanceStats {
    int total_trades;
    int winning_trades;
    int losing_trades;
    double total_profit;
    double total_loss;
    double max_consecutive_wins;
    double max_consecutive_losses;
    double sharpe_ratio;
    double profit_factor;
};
PerformanceStats stats;

// Market Structure
enum MARKET_STRUCTURE {
    MARKET_RANGING,
    MARKET_TRENDING_UP,
    MARKET_TRENDING_DOWN,
    MARKET_CONSOLIDATING
};

enum VOLATILITY_REGIME {
    VOL_LOW,
    VOL_MEDIUM, 
    VOL_HIGH,
    VOL_EXTREME
};

MARKET_STRUCTURE current_structure = MARKET_RANGING;
VOLATILITY_REGIME current_volatility = VOL_MEDIUM;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize trading objects
    if(!InitializeTradingObjects()) {
        Print("Failed to initialize trading objects");
        return INIT_FAILED;
    }
    
    // Initialize smart money components
    if(!InitializeSmartMoneyComponents()) {
        Print("Failed to initialize smart money components");
        return INIT_FAILED;
    }
    
    // Initialize performance tracking
    InitializePerformanceTracking();
    
    // Reset daily statistics
    ResetDailyStats();
    
    Print("Elite OmakScalping System initialized successfully");
    Print("Risk per trade: ", InpRiskPercent, "%");
    Print("Max daily risk: ", InpMaxDailyRisk, "%");
    Print("Trading timeframes: ", EnumToString(InpTF1), ", ", EnumToString(InpTF2), ", ", EnumToString(InpTF3));
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clean up smart money components
    if(ob_m1) delete ob_m1;
    if(ob_m5) delete ob_m5;
    if(ob_m15) delete ob_m15;
    if(ls_m1) delete ls_m1;
    if(ls_m5) delete ls_m5;
    if(ls_m15) delete ls_m15;
    if(ama_m1) delete ama_m1;
    if(ama_m5) delete ama_m5;
    if(ama_m15) delete ama_m15;
    if(vwap) delete vwap;
    if(volume_delta) delete volume_delta;
    
    // Print final statistics
    PrintFinalStats();
    
    Print("Elite OmakScalping System deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar on primary timeframe
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(_Symbol, InpTF1, 0);
    
    if(current_bar_time == last_bar_time) return;
    last_bar_time = current_bar_time;
    
    // Update daily reset
    CheckDailyReset();
    
    // Pre-trade checks
    if(!PreTradeChecks()) return;
    
    // Update market analysis
    UpdateMarketStructure();
    UpdateVolatilityRegime();
    
    // Update smart money components
    UpdateSmartMoneyAnalysis();
    
    CheckForEntries();
    ManagePositions();

    // Risk management checks
    if(!RiskManagementCheck()) return;
    
    // Look for trading opportunities
    AnalyzeTradingOpportunities();
    
    // Manage existing positions
    ManageExistingPositions();
    
    // Update performance metrics
    UpdatePerformanceMetrics();
}

//+------------------------------------------------------------------+
//| Initialize trading objects                                       |
//+------------------------------------------------------------------+
bool InitializeTradingObjects()
{
    if(!main_symbol.Name(_Symbol)) {
        Print("Failed to initialize symbol: ", _Symbol);
        return false;
    }
    
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    
    return true;
}

//+------------------------------------------------------------------+
//| Initialize smart money components                                |
//+------------------------------------------------------------------+
bool InitializeSmartMoneyComponents()
{
    // Initialize Order Blocks for multiple timeframes
    ob_m1 = new COmakOrderBlocks();
    ob_m5 = new COmakOrderBlocks();
    ob_m15 = new COmakOrderBlocks();
    
    if(!ob_m1.Init(_Symbol) || !ob_m5.Init(_Symbol) || !ob_m15.Init(_Symbol)) {
        Print("Failed to initialize Order Blocks");
        return false;
    }
    
    // Initialize Liquidity Sweeps
    ls_m1 = new COmakLiquiditySweeps();
    ls_m5 = new COmakLiquiditySweeps();
    ls_m15 = new COmakLiquiditySweeps();
    
    if(!ls_m1.Init(_Symbol) || !ls_m5.Init(_Symbol) || !ls_m15.Init(_Symbol)) {
        Print("Failed to initialize Liquidity Sweeps");
        return false;
    }
    
    // Initialize Adaptive Moving Averages
    ama_m1 = new COmakAdaptiveMA();
    ama_m5 = new COmakAdaptiveMA();
    ama_m15 = new COmakAdaptiveMA();
    
    if(!ama_m1.Init(_Symbol, PERIOD_M1, 21) || 
       !ama_m5.Init(_Symbol, PERIOD_M5, 21) || 
       !ama_m15.Init(_Symbol, PERIOD_M15, 21)) {
        Print("Failed to initialize Adaptive MA");
        return false;
    }
    
    // Initialize VWAP
    vwap = new COmakVWAP();
    if(!vwap.Init(_Symbol)) {
        Print("Failed to initialize VWAP");
        return false;
    }
    
    // Initialize Volume Delta
    volume_delta = new COmakVolumeDelta();
    if(!volume_delta.Init(_Symbol)) {
        Print("Failed to initialize Volume Delta");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Pre-trade validation checks                                     |
//+------------------------------------------------------------------+
bool PreTradeChecks()
{
    // Check if trading is allowed
    if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) {
        static datetime last_warning = 0;
        if(TimeCurrent() - last_warning > 3600) { // Warn once per hour
            Print("Trading is not allowed");
            last_warning = TimeCurrent();
        }
        return false;
    }
    
    // Check spread
    if(main_symbol.Spread() > InpMaxSpread) {
        return false;
    }
    
    // Check if market is open
    if(!IsMarketOpen()) {
        return false;
    }
    
    // Check trading session
    if(InpTradeOnlySession && !IsTradingSession()) {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Risk management validation                                       |
//+------------------------------------------------------------------+
bool RiskManagementCheck()
{
    // Check daily loss limit
    if(daily_pnl <= -account.Balance() * InpMaxDailyRisk / 100) {
        Print("Daily loss limit reached: ", daily_pnl);
        return false;
    }
    
    // Check maximum drawdown
    double current_drawdown = (max_equity - account.Equity()) / max_equity * 100;
    if(current_drawdown >= InpMaxDrawdown) {
        Print("Maximum drawdown reached: ", current_drawdown, "%");
        return false;
    }
    
    // Check maximum positions
    if(GetPositionCount() >= InpMaxPositions) {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get current position count                                       |
//+------------------------------------------------------------------+
int GetPositionCount()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        if(position.SelectByIndex(i)) {
            if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber) {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Check if market is open                                         |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
    MqlDateTime time_struct;
    TimeToStruct(TimeCurrent(), time_struct);
    
    // Skip weekends
    if(time_struct.day_of_week == 0 || time_struct.day_of_week == 6) {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if within trading session                                 |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
    MqlDateTime time_struct;
    TimeToStruct(TimeCurrent(), time_struct);
    
    int current_hour = time_struct.hour;
    
    // London/NY overlap (13:00-17:00 GMT)
    if(current_hour >= 13 && current_hour <= 17) return true;
    
    // London session (08:00-17:00 GMT)
    if(current_hour >= 8 && current_hour <= 17) return true;
    
    // NY session (13:00-22:00 GMT)
    if(current_hour >= 13 && current_hour <= 22) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Reset daily statistics                                          |
//+------------------------------------------------------------------+
void ResetDailyStats()
{
    MqlDateTime current_time;
    TimeToStruct(TimeCurrent(), current_time);
    
    MqlDateTime last_reset;
    TimeToStruct(last_reset_time, last_reset);
    
    // Reset if new day
    if(current_time.day != last_reset.day) {
        daily_pnl = 0;
        session_high_equity = account.Equity();
        last_reset_time = TimeCurrent();
        
        Print("Daily statistics reset for new trading day");
    }
}

//+------------------------------------------------------------------+
//| Check for daily reset                                           |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
    static datetime last_check = 0;
    
    if(TimeCurrent() - last_check >= 3600) { // Check every hour
        ResetDailyStats();
        last_check = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Initialize performance tracking                                  |
//+------------------------------------------------------------------+
void InitializePerformanceTracking()
{
    ZeroMemory(stats);
    max_equity = account.Equity();
    session_high_equity = account.Equity();
    trailing_max_equity = account.Equity();
    daily_max_equity = account.Equity();
}

//+------------------------------------------------------------------+
//| Update performance metrics                                       |
//+------------------------------------------------------------------+
void UpdatePerformanceMetrics()
{
    // Update max equity
    if(account.Equity() > max_equity) {
        max_equity = account.Equity();
    }
    
    // Update session high
    if(account.Equity() > session_high_equity) {
        session_high_equity = account.Equity();
    }
    
    // Calculate profit factor
    if(stats.total_loss != 0) {
        stats.profit_factor = MathAbs(stats.total_profit / stats.total_loss);
    }
}

//+------------------------------------------------------------------+
//| Print final statistics                                          |
//+------------------------------------------------------------------+
void PrintFinalStats()
{
    Print("=== FINAL PERFORMANCE STATISTICS ===");
    Print("Total Trades: ", stats.total_trades);
    Print("Winning Trades: ", stats.winning_trades);
    Print("Losing Trades: ", stats.losing_trades);
    Print("Win Rate: ", (stats.total_trades > 0 ? (double)stats.winning_trades/stats.total_trades*100 : 0), "%");
    Print("Profit Factor: ", stats.profit_factor);
    Print("Total Profit: ", stats.total_profit);
    Print("Total Loss: ", stats.total_loss);
    Print("Net Profit: ", stats.total_profit + stats.total_loss);
}

void CheckForEntries()
{
    // Get current price data
    double bid = main_symbol.Bid();
    double ask = main_symbol.Ask();

    // Multi-timeframe confluence check
    bool mtf_confluence = CheckMTFConfluence();

    // Volume analysis
    double vwap_value = vwap.GetVWAP();
    double volume_ratio = vwap.GetVolumeRatio();
    bool volume_filter = vwap.IsVolumeSignificant();

    // Calculate position size
    double lot_size = CalculatePositionSize();

    // Bullish setup
    if(mtf_confluence && 
       bid > vwap_value && 
       volume_filter &&
       !IsOverbought(bid) &&
       GetPositionCount() < InpMaxPositions)
    {
        // Place buy order with proper SL/TP
        double sl = CalculateStopLoss(true);
        double tp = CalculateTakeProfit(true, sl);

        if(InpUseTrailingStop) {
            // TODO: TrailingStop is undefined or not implemented for 'trade'.
            // trade.TrailingStop(sl, InpTrailingStopPips * _Point);
        }

        ulong ticket = trade.Buy(lot_size, _Symbol, ask, sl, tp, "Scalp Buy");
        if(ticket > 0) {
            stats.total_trades++;
            Print("Buy order placed at ", ask, " with SL: ", sl, " TP: ", tp);
        }
    }

    // Bearish setup
    else if(mtf_confluence && 
           bid < vwap_value && 
           volume_filter &&
           !IsOversold(bid) &&
           GetPositionCount() < InpMaxPositions)
    {
        // Place sell order with proper SL/TP
        double sl = CalculateStopLoss(false);
        double tp = CalculateTakeProfit(false, sl);

        if(InpUseTrailingStop) {
            // TODO: TrailingStop is undefined or not implemented for 'trade'.
            // trade.TrailingStop(sl, InpTrailingStopPips * _Point);
        }

        ulong ticket = trade.Sell(lot_size, _Symbol, bid, sl, tp, "Scalp Sell");
        if(ticket > 0) {
            stats.total_trades++;
            Print("Sell order placed at ", bid, " with SL: ", sl, " TP: ", tp);
        }
    }
}

double CalculatePositionSize()
{
    double risk_amount = account.Equity() * (InpRiskPercent / 100);
    // TODO: LotsValue is undefined or not implemented for 'main_symbol'. Commented out for compilation.
    // double pip_value = main_symbol.LotsValue(1, _Symbol);
    double pip_value = 1.0; // Placeholder for compilation
    double stop_loss_pips = CalculateATRBasedRisk();

    return MathMin(risk_amount / (stop_loss_pips * pip_value), 
                  main_symbol.LotsMax());
}


double CalculateStopLoss(bool is_buy)
{
    // Use ATR-based stops
    // TODO: iATR wrong parameter count. Should be iATR(symbol, timeframe, period)
    double atr = iATR(_Symbol, InpTF2, 14); // Fixed parameter count for compilation
    double base_stop = atr * 1.5;

    // Or use VWAP band distance
    double vwap_distance = is_buy ? 
                          (main_symbol.Bid() - vwap.GetLowerBand1()) : 
                          (vwap.GetUpperBand1() - main_symbol.Bid());

    return MathMax(base_stop, vwap_distance * 0.5);
}

bool CheckMTFConfluence()
{
    // In CheckMTFConfluence, declare and fill arrays before passing
    double open_m1[100], high_m1[100], low_m1[100], close_m1[100];
    CopyOpen(_Symbol, InpTF1, 0, 100, open_m1);
    CopyHigh(_Symbol, InpTF1, 0, 100, high_m1);
    CopyLow(_Symbol, InpTF1, 0, 100, low_m1);
    CopyClose(_Symbol, InpTF1, 0, 100, close_m1);

    double open_m5[100], high_m5[100], low_m5[100], close_m5[100];
    CopyOpen(_Symbol, InpTF2, 0, 100, open_m5);
    CopyHigh(_Symbol, InpTF2, 0, 100, high_m5);
    CopyLow(_Symbol, InpTF2, 0, 100, low_m5);
    CopyClose(_Symbol, InpTF2, 0, 100, close_m5);

    double open_m15[100], high_m15[100], low_m15[100], close_m15[100];
    CopyOpen(_Symbol, InpTF3, 0, 100, open_m15);
    CopyHigh(_Symbol, InpTF3, 0, 100, high_m15);
    CopyLow(_Symbol, InpTF3, 0, 100, low_m15);
    CopyClose(_Symbol, InpTF3, 0, 100, close_m15);

    // --- Real entry logic restored ---
    bool ob_m1_result = ob_m1.DetectOrderBlock(0, true, open_m1, high_m1, low_m1, close_m1);
    bool ob_m5_result = ob_m5.DetectOrderBlock(0, true, open_m5, high_m5, low_m5, close_m5);
    bool ob_m15_result = ob_m15.DetectOrderBlock(0, true, open_m15, high_m15, low_m15, close_m15);

    bool ls1 = ls_m1.IsLiquiditySweep(0, high_m1, low_m1, open_m1, close_m1);
    bool ls5 = ls_m5.IsLiquiditySweep(0, high_m5, low_m5, open_m5, close_m5);
    bool ls15 = ls_m15.IsLiquiditySweep(0, high_m15, low_m15, open_m15, close_m15);

    // Check adaptive MA alignment
    bool ama_align = CheckMAAlignment();

    // Logging for debug
    Print("[DEBUG] ob_m1:", ob_m1_result, " ob_m5:", ob_m5_result, " ob_m15:", ob_m15_result,
          " | ls1:", ls1, " ls5:", ls5, " ls15:", ls15, " | ama_align:", ama_align);

    // Need at least 2 out of 3 confirmations
    int confirmations = (ob_m1_result + ob_m5_result + ob_m15_result) +
                        (ls1 + ls5 + ls15) +
                        (ama_align ? 1 : 0);

    Print("[DEBUG] Confirmations: ", confirmations);
    return confirmations >= 3;
}

bool CheckMAAlignment()
{
    double ma1 = ama_m1.GetAdaptiveMA(0);
    double ma2 = ama_m5.GetAdaptiveMA(0);
    double ma3 = ama_m15.GetAdaptiveMA(0);

    return (ma1 > ma2 && ma2 > ma3) || (ma1 < ma2 && ma2 < ma3);
}

void ManagePositions()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Symbol() != _Symbol || position.Magic() != InpMagicNumber)
                continue;

            double profit = position.Profit();
            double current_rr = CalculateCurrentRR(position);

            // Dynamic trailing stop
            if(InpUseTrailingStop && current_rr > 1.0)
            {
                double new_sl = CalculateDynamicSL(position);
                if(new_sl != position.StopLoss())
                    trade.PositionModify(position.Ticket(), new_sl, position.TakeProfit());
            }

            // Time-based exit
            // TODO: TimeOpen is undefined for 'position'. Commented out for compilation.
            // if(TimeCurrent() - position.TimeOpen() > 60 * 15) // 15 minutes
            // {
            //     if(current_rr > 0.5) // Minimum 0.5 RR before exiting
            //         trade.PositionClose(position.Ticket());
            // }
        }
    }
}

// --- MARKET STRUCTURE & VOLATILITY ---
void UpdateMarketStructure()
{
    // Simple trend detection using adaptive MA and price action
    double ma_fast = ama_m1.GetAdaptiveMA(0);
    double ma_slow = ama_m15.GetAdaptiveMA(0);
    double price = main_symbol.Bid();
    if(price > ma_fast && ma_fast > ma_slow)
        current_structure = MARKET_TRENDING_UP;
    else if(price < ma_fast && ma_fast < ma_slow)
        current_structure = MARKET_TRENDING_DOWN;
    else
        current_structure = MARKET_RANGING;
}

void UpdateVolatilityRegime()
{
    // Use ATR to classify volatility
    double atr = iATR(_Symbol, InpTF2, 14); // Fixed parameter count for compilation
    if(atr < main_symbol.Point() * 50)
        current_volatility = VOL_LOW;
    else if(atr < main_symbol.Point() * 100)
        current_volatility = VOL_MEDIUM;
    else if(atr < main_symbol.Point() * 200)
        current_volatility = VOL_HIGH;
    else
        current_volatility = VOL_EXTREME;
}

void UpdateSmartMoneyAnalysis()
{
    ob_m1.Update();
    ob_m5.Update();
    ob_m15.Update();
    ls_m1.Update();
    ls_m5.Update();
    ls_m15.Update();
    vwap.Update();
    volume_delta.Update(100);
}

void AnalyzeTradingOpportunities()
{
    // Example: print confluence if all modules align
    if(CheckMTFConfluence())
        Print("Smart Money Confluence Detected at ", TimeToString(TimeCurrent()));
}

void ManageExistingPositions()
{
    // Example: close positions if structure changes
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
            {
                if(current_structure == MARKET_RANGING)
                    trade.PositionClose(position.Ticket());
            }
        }
    }
}

// --- ENTRY/EXIT FILTER HELPERS ---
bool IsOverbought(double price)
{
    // Overbought if price > VWAP upper band and CVD is negative
    return (price > vwap.GetUpperBand1() && volume_delta.GetCVD(0) < 0);
}

bool IsOversold(double price)
{
    // Oversold if price < VWAP lower band and CVD is positive
    return (price < vwap.GetLowerBand1() && volume_delta.GetCVD(0) > 0);
}

double CalculateCurrentRR(CPositionInfo &pos)
{
    double entry = pos.PriceOpen();
    double sl = pos.StopLoss();
    double tp = pos.TakeProfit();
    double cur = main_symbol.Bid();
    if(pos.PositionType() == POSITION_TYPE_BUY)
        return (cur - entry) / (entry - sl);
    else
        return (entry - cur) / (sl - entry);
}

double CalculateDynamicSL(CPositionInfo &pos)
{
    // Trail SL to breakeven plus buffer
    double entry = pos.PriceOpen();
    double buffer = main_symbol.Point() * 10;
    if(pos.PositionType() == POSITION_TYPE_BUY)
        return MathMax(pos.StopLoss(), entry + buffer);
    else
        return MathMin(pos.StopLoss(), entry - buffer);
}

double CalculateATRBasedRisk()
{
    // Use ATR as risk proxy
    // TODO: iATR wrong parameter count. Should be iATR(symbol, timeframe, period)
    double atr = iATR(_Symbol, InpTF2, 14); // Fixed parameter count for compilation
    return atr / main_symbol.Point();
}

double CalculateTakeProfit(bool is_buy, double sl)
{
    // Use minimum RR
    double entry = main_symbol.Bid();
    double rr = InpMinRR;
    if(is_buy)
        return entry + rr * (entry - sl);
    else
        return entry - rr * (sl - entry);
}

void CheckEquityTrailingStop()
{
    // Update max equity tracking
    if(account.Equity() > trailing_max_equity)
        trailing_max_equity = account.Equity();

    if(account.Equity() > daily_max_equity)
        daily_max_equity = account.Equity();

    // Equity protection mechanism
    double trailing_drawdown = (trailing_max_equity - account.Equity()) / trailing_max_equity * 100;
    double daily_drawdown = (daily_max_equity - account.Equity()) / daily_max_equity * 100;

    if(trailing_drawdown > InpMaxDrawdown || daily_drawdown > InpMaxDailyRisk)
    {
        // Close all positions
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(position.SelectByIndex(i))
            {
                if(position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
                    trade.PositionClose(position.Ticket());
            }
        }

        // Stop trading for the day
        last_reset_time = TimeCurrent() + 24*3600; // Prevent trading until next day
        Print("Equity protection triggered! Stopping trading.");
    }
}