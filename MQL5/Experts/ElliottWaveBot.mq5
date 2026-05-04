//+------------------------------------------------------------------+
//|                                              ElliottWaveBot.mq5 |
//|                       Professional Elliott Wave Expert Advisor  |
//|                                                                  |
//|  Implements the strict rules of the Elliott Wave Principle as    |
//|  described in Frost & Prechter's reference book of the same      |
//|  name. The bot:                                                  |
//|    - Detects swing pivots with a self-contained ZigZag.          |
//|    - Identifies the most recent 5-wave impulse and (optional)    |
//|      ABC corrective sequence from those pivots.                  |
//|    - Validates the three Cardinal Rules (R1, R2, R3) on every    |
//|      candidate count and aborts trade entries when they fail.    |
//|    - Scores Fibonacci guideline matches (W2/W4 retracements,     |
//|      W3/W5 extensions, alternation) into a 0-100 confidence.     |
//|    - Builds Entry / SL / TP1 / TP2 / TP3 levels with R/R for     |
//|      either a "Wave 4 -> Wave 5" continuation or an "End of C    |
//|      -> new impulse" reversal.                                   |
//|    - Sizes positions by % of balance and respects broker         |
//|      volume constraints.                                         |
//|    - Renders an on-chart HUD panel + numbered wave labels +      |
//|      Entry/SL/TP horizontal lines, matching the look of the      |
//|      reference Elliott Wave Analyzer screenshot.                 |
//|                                                                  |
//|  This is an Expert Advisor (not an indicator). Attach it to a    |
//|  chart from MetaTrader 5 -> Navigator -> Expert Advisors.        |
//+------------------------------------------------------------------+
#property copyright "Elliott Wave Bot"
#property link      "https://github.com/jnayzn/elliott-wave-bot"
#property version   "1.00"
#property strict
#property description "Professional Elliott Wave EA for MT5 - based on Frost & Prechter's Elliott Wave Principle."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

#include <ElliottWave\ZigZagDetector.mqh>
#include <ElliottWave\FiboRatios.mqh>
#include <ElliottWave\WaveCounter.mqh>
#include <ElliottWave\TradeSetup.mqh>
#include <ElliottWave\RiskManager.mqh>
#include <ElliottWave\HUDPanel.mqh>

//============================== INPUTS =============================
input group "ZigZag (pivot detection)"
input int    InpZZDepth         = 12;     // ZigZag Depth (bars)
input int    InpZZDeviation     = 5;      // ZigZag Deviation (points)
input int    InpZZBackstep      = 3;      // ZigZag Backstep (bars)
input int    InpHistoryBars     = 1500;   // Bars to scan for pivots
input int    InpMaxPivots       = 12;     // Max pivots to consider

input group "Elliott analysis"
input int    InpMinConfidence   = 60;     // Min confidence (0-100) to trade
input bool   InpRequireAllRules = true;   // Refuse trade if any cardinal rule broken
input bool   InpAllowW4ToW5     = true;   // Enable W4 -> W5 continuation setup
input bool   InpAllowEndOfC     = true;   // Enable End-of-C reversal setup

input group "Risk management"
input double InpRiskPercent     = 1.0;    // Risk per trade (% balance)
input double InpMinRR           = 1.5;    // Minimum R/R to take a trade
input double InpSLBufferPoints  = 50;     // SL buffer beyond invalidation pivot (points)
input bool   InpAutoTrade       = false;  // Place market orders automatically

input group "Display"
input bool   InpShowHUD         = true;   // Draw HUD panel + wave labels
input int    InpHUDX            = 12;     // HUD top-left X (px)
input int    InpHUDY            = 32;     // HUD top-left Y (px)
input int    InpMagic           = 730501; // Magic number

//============================ GLOBAL STATE =========================
CTrade          g_trade;
CPositionInfo   g_pos;

EwbHUDConfig    g_hud;
EwbWaveCount    g_wc;
EwbTradeSetup   g_setup;
EwbPivot        g_pivots[];

datetime        g_last_bar_time = 0;

#define EWB_PREFIX "EWB_"

//+------------------------------------------------------------------+
//|  Try to compute a fresh wave count + setup from current data.   |
//|  Returns true if a count was identified (even partial).         |
//+------------------------------------------------------------------+
bool RecomputeAnalysis()
{
   const int look = MathMin(InpHistoryBars, Bars(_Symbol, _Period));
   if(look < InpZZDepth * 4) return false;

   double  high[];
   double  low[];
   datetime time[];
   ArraySetAsSeries(high, false);
   ArraySetAsSeries(low,  false);
   ArraySetAsSeries(time, false);

   if(CopyHigh(_Symbol, _Period, 0, look, high) <= 0) return false;
   if(CopyLow (_Symbol, _Period, 0, look, low)  <= 0) return false;
   if(CopyTime(_Symbol, _Period, 0, look, time) <= 0) return false;

   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   int n_pivots = EwbDetectPivots(high, low, time, look,
                                  InpZZDepth, InpZZDeviation, InpZZBackstep,
                                  point, InpMaxPivots, g_pivots);
   if(n_pivots < 4)
   {
      EwbInitWaveCount(g_wc);
      EwbInitTradeSetup(g_setup);
      return false;
   }

   bool ok = EwbAnalyseWaves(g_pivots, g_wc);

   EwbInitTradeSetup(g_setup);
   if(ok)
   {
      EwbTradeSetup ts_c, ts_w;
      bool has_c = InpAllowEndOfC && EwbBuildEndOfCSetup(g_wc, InpSLBufferPoints, point, ts_c);
      bool has_w = InpAllowW4ToW5 && EwbBuildW4toW5Setup(g_wc, InpSLBufferPoints, point, ts_w);

      if(has_c && has_w)
      {
         if(ts_c.rr >= ts_w.rr) g_setup = ts_c;
         else                   g_setup = ts_w;
      }
      else if(has_c) g_setup = ts_c;
      else if(has_w) g_setup = ts_w;
   }
   return ok;
}

//+------------------------------------------------------------------+
//|  Returns true if there is already an open position from this EA. |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(g_pos.SelectByIndex(i))
      {
         if(g_pos.Magic() == InpMagic && g_pos.Symbol() == _Symbol)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//|  Place a market order matching the current setup.               |
//+------------------------------------------------------------------+
void TryPlaceTrade()
{
   if(!InpAutoTrade) return;
   if(!g_setup.valid) return;
   if(g_wc.confidence < InpMinConfidence) return;
   if(g_setup.rr < InpMinRR) return;
   if(HasOpenPosition()) return;

   if(InpRequireAllRules)
   {
      if(!g_wc.rule_w2_no_full_retrace) return;
      if(!g_wc.rule_w3_not_shortest)    return;
      if(!g_wc.rule_w4_no_overlap)      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price_now = (g_setup.side == EWB_SETUP_SIDE_BUY) ? ask : bid;

   // Sanity: is the current price reasonably close to the entry?
   double dist_to_entry = MathAbs(price_now - g_setup.entry);
   double atr_proxy     = MathAbs(g_setup.tp1 - g_setup.entry);
   if(atr_proxy > 0.0 && dist_to_entry > atr_proxy)
      return; // signal too stale

   double sl_dist = MathAbs(price_now - g_setup.sl);
   if(sl_dist <= 0.0) return;

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double vol_min    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vol_step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);

   double lots = EwbComputeLotSize(balance, InpRiskPercent, sl_dist,
                                   tick_value, tick_size,
                                   vol_min, vol_max, vol_step);
   if(lots < vol_min) return;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   bool sent = false;
   string comment = StringFormat("EWB %s [%d/100]", g_setup.label, g_wc.confidence);
   if(g_setup.side == EWB_SETUP_SIDE_BUY)
      sent = g_trade.Buy(lots, _Symbol, ask, g_setup.sl, g_setup.tp1, comment);
   else if(g_setup.side == EWB_SETUP_SIDE_SELL)
      sent = g_trade.Sell(lots, _Symbol, bid, g_setup.sl, g_setup.tp1, comment);

   if(!sent)
   {
      Print("EWB trade failed: ", g_trade.ResultRetcode(), " ",
            g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//|  Render everything on-chart based on the latest analysis.       |
//+------------------------------------------------------------------+
void RenderAll()
{
   if(!InpShowHUD)
   {
      EwbDestroyAll(EWB_PREFIX);
      return;
   }
   EwbRenderPanel(g_hud, _Symbol, _Period, TimeCurrent(), g_wc, g_setup);
   EwbRenderWaveOverlay(g_hud, g_wc);
   EwbRenderTradeLines(g_hud, g_setup);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   EwbDefaultHUDConfig(g_hud, EWB_PREFIX);
   g_hud.x = InpHUDX;
   g_hud.y = InpHUDY;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);

   EwbDestroyAll(EWB_PREFIX);
   RecomputeAnalysis();
   RenderAll();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EwbDestroyAll(EWB_PREFIX);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert tick                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime curr_bar = iTime(_Symbol, _Period, 0);
   bool new_bar = (curr_bar != g_last_bar_time);

   if(new_bar)
   {
      g_last_bar_time = curr_bar;
      RecomputeAnalysis();
      RenderAll();
      TryPlaceTrade();
   }
   else if(InpShowHUD)
   {
      // Light refresh of the "Updated" timestamp on tick.
      EwbEnsureLabel(g_hud.prefix + "val_upd", g_hud,
                     g_hud.x + 90,
                     g_hud.y + g_hud.line_height + 12 + g_hud.line_height * 2,
                     TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
                     g_hud.value_color);
   }
}

//+------------------------------------------------------------------+
//| Chart event handler — clicks on the SYNC button force a refresh. |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == EWB_PREFIX + "sync_btn")
      {
         RecomputeAnalysis();
         RenderAll();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
   }
}

//+------------------------------------------------------------------+
