//+------------------------------------------------------------------+
//|                                              ZigZagDetector.mqh |
//|                                    Elliott Wave Bot — Pivots    |
//+------------------------------------------------------------------+
//|  Self-contained ZigZag-style swing pivot detector.               |
//|                                                                  |
//|  We deliberately re-implement ZigZag here instead of using the   |
//|  built-in iCustom("ZigZag",...) call so the EA has no external   |
//|  indicator dependency and behaves identically across brokers.    |
//|                                                                  |
//|  Algorithm (classic MetaQuotes ZigZag):                          |
//|    - Depth     : minimum number of bars between two extrema.     |
//|    - Deviation : minimum reversal in points to register a pivot. |
//|    - Backstep  : minimum bar distance between alternating pivots.|
//+------------------------------------------------------------------+
#property copyright "Elliott Wave Bot"
#property strict
#ifndef __EWB_ZIGZAG_DETECTOR_MQH__
#define __EWB_ZIGZAG_DETECTOR_MQH__

enum EwbPivotType
{
   EWB_PIVOT_NONE = 0,
   EWB_PIVOT_HIGH = 1,
   EWB_PIVOT_LOW  = -1
};

struct EwbPivot
{
   datetime      time;     // bar open time
   double        price;    // pivot price (high or low)
   int           bar;      // bar index (0 = oldest of the local copy)
   EwbPivotType  type;     // EWB_PIVOT_HIGH or EWB_PIVOT_LOW
};

//+------------------------------------------------------------------+
//|  Detect the last `maxPivots` ZigZag pivots on the supplied bars. |
//|  Output array is ordered oldest-first.                           |
//|  Returns the number of pivots actually written.                  |
//+------------------------------------------------------------------+
int EwbDetectPivots(const double &high[],
                    const double &low[],
                    const datetime &time[],
                    const int rates_total,
                    const int depth,
                    const int deviation,
                    const int backstep,
                    const double point_size,
                    const int maxPivots,
                    EwbPivot &out_pivots[])
{
   ArrayResize(out_pivots, 0);
   if(rates_total < depth * 2 + 10) return 0;

   // Internal buffers, indexed bar 0 = oldest, bar rates_total-1 = newest.
   double zz_high[]; ArrayResize(zz_high, rates_total); ArrayInitialize(zz_high, 0.0);
   double zz_low[];  ArrayResize(zz_low,  rates_total); ArrayInitialize(zz_low,  0.0);

   double last_high = 0.0;
   double last_low  = 0.0;

   // Pass 1 — local extrema with `depth` lookback.
   for(int i = depth; i < rates_total; ++i)
   {
      double maxv = high[i];
      int    maxp = i;
      for(int k = i - depth + 1; k <= i; ++k)
      {
         if(high[k] > maxv) { maxv = high[k]; maxp = k; }
      }
      if(maxp == i && (last_high == 0.0 || (maxv - last_high) > deviation * point_size))
      {
         zz_high[i] = maxv;
      }

      double minv = low[i];
      int    minp = i;
      for(int k = i - depth + 1; k <= i; ++k)
      {
         if(low[k] < minv) { minv = low[k]; minp = k; }
      }
      if(minp == i && (last_low == 0.0 || (last_low - minv) > deviation * point_size))
      {
         zz_low[i] = minv;
      }
   }

   // Pass 2 — alternation enforcement: replace consecutive same-type pivots
   // by the more extreme one, keep alternating high/low/high/low... with
   // a minimum bar separation of `backstep`.
   EwbPivot raw[];
   ArrayResize(raw, 0);

   int    last_type = 0; // 1 high, -1 low
   double last_price = 0.0;
   int    last_bar = -10000;

   for(int i = 0; i < rates_total; ++i)
   {
      if(zz_high[i] != 0.0)
      {
         if(last_type == 1)
         {
            if(zz_high[i] >= last_price && ArraySize(raw) > 0)
            {
               int n = ArraySize(raw) - 1;
               raw[n].time  = time[i];
               raw[n].price = zz_high[i];
               raw[n].bar   = i;
               raw[n].type  = EWB_PIVOT_HIGH;
               last_price = zz_high[i];
               last_bar = i;
            }
         }
         else if(i - last_bar >= backstep || last_type == 0)
         {
            EwbPivot p;
            p.time  = time[i];
            p.price = zz_high[i];
            p.bar   = i;
            p.type  = EWB_PIVOT_HIGH;
            int n = ArraySize(raw);
            ArrayResize(raw, n + 1);
            raw[n] = p;
            last_type  = 1;
            last_price = zz_high[i];
            last_bar   = i;
         }
      }
      if(zz_low[i] != 0.0)
      {
         if(last_type == -1)
         {
            if(zz_low[i] <= last_price && ArraySize(raw) > 0)
            {
               int n = ArraySize(raw) - 1;
               raw[n].time  = time[i];
               raw[n].price = zz_low[i];
               raw[n].bar   = i;
               raw[n].type  = EWB_PIVOT_LOW;
               last_price = zz_low[i];
               last_bar = i;
            }
         }
         else if(i - last_bar >= backstep || last_type == 0)
         {
            EwbPivot p;
            p.time  = time[i];
            p.price = zz_low[i];
            p.bar   = i;
            p.type  = EWB_PIVOT_LOW;
            int n = ArraySize(raw);
            ArrayResize(raw, n + 1);
            raw[n] = p;
            last_type  = -1;
            last_price = zz_low[i];
            last_bar   = i;
         }
      }
   }

   int total = ArraySize(raw);
   int keep  = MathMin(total, maxPivots);
   ArrayResize(out_pivots, keep);
   for(int j = 0; j < keep; ++j)
      out_pivots[j] = raw[total - keep + j];
   return keep;
}

#endif // __EWB_ZIGZAG_DETECTOR_MQH__
