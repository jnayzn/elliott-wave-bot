//+------------------------------------------------------------------+
//|                                                 TradeSetup.mqh  |
//|                                Elliott Wave Bot — Trade levels  |
//+------------------------------------------------------------------+
//|  Translates a validated WaveCount into concrete entry / SL /     |
//|  TP1 / TP2 / TP3 levels, and computes risk-reward.               |
//|                                                                  |
//|  Setup library (Frost & Prechter best-practice trades):          |
//|                                                                  |
//|  A) Wave 4 -> Wave 5 continuation                                |
//|       Entry  : break of W3 high  (or limit at W4 close)          |
//|       SL     : just beyond W1 high (cannot overlap, R3)          |
//|       TP1    : 100% projection of W1 from W4 (W5=W1 equality)    |
//|       TP2    : 1.618 projection of W1 from W4                    |
//|       TP3    : 2.618 projection of W1 from W4                    |
//|                                                                  |
//|  B) End of C -> new impulse (status = ABC_COMPLETE).             |
//|       Entry  : current price (or limit at C pivot)               |
//|       SL     : just beyond C pivot                               |
//|       TP1    : .382 retrace of the prior 5-wave move from C      |
//|       TP2    : .618 retrace of the prior 5-wave move from C      |
//|       TP3    : 1.000 retrace of the prior 5-wave move from C     |
//+------------------------------------------------------------------+
#property copyright "Elliott Wave Bot"
#property strict
#ifndef __EWB_TRADE_SETUP_MQH__
#define __EWB_TRADE_SETUP_MQH__

#include "WaveCounter.mqh"
#include "FiboRatios.mqh"

enum EwbSetupKind
{
   EWB_SETUP_NONE     = 0,
   EWB_SETUP_W4_TO_W5 = 1,
   EWB_SETUP_END_OF_C = 2
};

enum EwbSetupSide
{
   EWB_SETUP_SIDE_NONE = 0,
   EWB_SETUP_SIDE_BUY  = 1,
   EWB_SETUP_SIDE_SELL = -1
};

struct EwbTradeSetup
{
   EwbSetupKind kind;
   EwbSetupSide side;
   double       entry;
   double       sl;
   double       tp1;
   double       tp2;
   double       tp3;
   double       rr;       // R/R based on entry->TP1 versus entry->SL distance.
   bool         valid;
   string       label;
};

void EwbInitTradeSetup(EwbTradeSetup &ts)
{
   ts.kind  = EWB_SETUP_NONE;
   ts.side  = EWB_SETUP_SIDE_NONE;
   ts.entry = 0.0;
   ts.sl    = 0.0;
   ts.tp1   = 0.0;
   ts.tp2   = 0.0;
   ts.tp3   = 0.0;
   ts.rr    = 0.0;
   ts.valid = false;
   ts.label = "";
}

//+------------------------------------------------------------------+
//|  Build a Wave 4 -> Wave 5 continuation setup.                   |
//+------------------------------------------------------------------+
bool EwbBuildW4toW5Setup(const EwbWaveCount &wc, const double sl_buffer_points,
                         const double point_size, EwbTradeSetup &ts)
{
   EwbInitTradeSetup(ts);
   if(wc.direction == EWB_WAVE_DIR_NONE) return false;
   if(wc.status < EWB_WAVE_STATUS_IMPULSE_DONE) return false;

   double w1_start = wc.p0.price;
   double w1_end   = wc.p1.price;
   double w3_end   = wc.p3.price;
   double w4_end   = wc.p4.price;
   double len_w1   = MathAbs(w1_end - w1_start);
   double buffer   = sl_buffer_points * point_size;

   ts.kind  = EWB_SETUP_W4_TO_W5;
   ts.label = "W4 -> W5 continuation";

   if(wc.direction == EWB_WAVE_DIR_BULLISH)
   {
      ts.side  = EWB_SETUP_SIDE_BUY;
      ts.entry = w3_end;
      ts.sl    = w1_end - buffer;
      ts.tp1   = w4_end + len_w1 * EWB_FIBO_1000;
      ts.tp2   = w4_end + len_w1 * EWB_FIBO_1618;
      ts.tp3   = w4_end + len_w1 * EWB_FIBO_2618;
   }
   else
   {
      ts.side  = EWB_SETUP_SIDE_SELL;
      ts.entry = w3_end;
      ts.sl    = w1_end + buffer;
      ts.tp1   = w4_end - len_w1 * EWB_FIBO_1000;
      ts.tp2   = w4_end - len_w1 * EWB_FIBO_1618;
      ts.tp3   = w4_end - len_w1 * EWB_FIBO_2618;
   }

   double risk   = MathAbs(ts.entry - ts.sl);
   double reward = MathAbs(ts.tp1   - ts.entry);
   ts.rr = (risk > 0.0) ? (reward / risk) : 0.0;
   ts.valid = (risk > 0.0) && (ts.rr > 0.0);
   return ts.valid;
}

//+------------------------------------------------------------------+
//|  Build an End-of-C -> new impulse reversal setup.                |
//+------------------------------------------------------------------+
bool EwbBuildEndOfCSetup(const EwbWaveCount &wc, const double sl_buffer_points,
                         const double point_size, EwbTradeSetup &ts)
{
   EwbInitTradeSetup(ts);
   if(wc.status != EWB_WAVE_STATUS_ABC_COMPLETE) return false;

   double w0 = wc.p0.price;
   double w5 = wc.p5.price;
   double pc = wc.pC.price;
   double len_5 = MathAbs(w5 - w0);
   if(len_5 <= 0.0) return false;

   ts.kind  = EWB_SETUP_END_OF_C;
   ts.label = "End of C -> new impulse";

   double buffer = sl_buffer_points * point_size;

   if(wc.bias == EWB_WAVE_DIR_BULLISH)
   {
      ts.side  = EWB_SETUP_SIDE_BUY;
      ts.entry = pc;
      ts.sl    = pc - buffer;
      ts.tp1   = pc + len_5 * EWB_FIBO_382;
      ts.tp2   = pc + len_5 * EWB_FIBO_618;
      ts.tp3   = pc + len_5 * EWB_FIBO_1000;
   }
   else if(wc.bias == EWB_WAVE_DIR_BEARISH)
   {
      ts.side  = EWB_SETUP_SIDE_SELL;
      ts.entry = pc;
      ts.sl    = pc + buffer;
      ts.tp1   = pc - len_5 * EWB_FIBO_382;
      ts.tp2   = pc - len_5 * EWB_FIBO_618;
      ts.tp3   = pc - len_5 * EWB_FIBO_1000;
   }
   else
   {
      return false;
   }

   double risk   = MathAbs(ts.entry - ts.sl);
   double reward = MathAbs(ts.tp1   - ts.entry);
   ts.rr = (risk > 0.0) ? (reward / risk) : 0.0;
   ts.valid = (risk > 0.0) && (ts.rr > 0.0);
   return ts.valid;
}

//+------------------------------------------------------------------+
//|  Pick the best applicable setup for a given count.              |
//+------------------------------------------------------------------+
bool EwbBuildBestSetup(const EwbWaveCount &wc, const double sl_buffer_points,
                       const double point_size, EwbTradeSetup &ts)
{
   if(EwbBuildEndOfCSetup(wc, sl_buffer_points, point_size, ts)) return true;
   if(EwbBuildW4toW5Setup(wc, sl_buffer_points, point_size, ts)) return true;
   EwbInitTradeSetup(ts);
   return false;
}

#endif // __EWB_TRADE_SETUP_MQH__
