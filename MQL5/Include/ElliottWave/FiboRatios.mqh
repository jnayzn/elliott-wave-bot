//+------------------------------------------------------------------+
//|                                                  FiboRatios.mqh |
//|                                       Elliott Wave Bot — Helpers |
//+------------------------------------------------------------------+
//|  Fibonacci constants and helpers used throughout the wave        |
//|  counter and trade-setup modules.                                |
//|                                                                  |
//|  Reference: Frost & Prechter, "Elliott Wave Principle"           |
//|    - Sharp corrections (W2, B of zigzag, X) tend to retrace      |
//|      .618 or .500 of the previous wave.                          |
//|    - Sideways corrections (W4, flats) tend to retrace .382.      |
//|    - Motive waves typically relate by .618, 1.0, 1.618, 2.618.   |
//+------------------------------------------------------------------+
#property copyright "Elliott Wave Bot"
#property strict
#ifndef __EWB_FIBO_RATIOS_MQH__
#define __EWB_FIBO_RATIOS_MQH__

// Common Fibonacci ratios used in Elliott analysis.
#define EWB_FIBO_236  0.236
#define EWB_FIBO_382  0.382
#define EWB_FIBO_500  0.500
#define EWB_FIBO_618  0.618
#define EWB_FIBO_786  0.786
#define EWB_FIBO_1000 1.000
#define EWB_FIBO_1272 1.272
#define EWB_FIBO_1618 1.618
#define EWB_FIBO_2000 2.000
#define EWB_FIBO_2618 2.618
#define EWB_FIBO_4236 4.236

//+------------------------------------------------------------------+
//|  Returns the price level of a retracement of `ratio` between two |
//|  pivots.                                                         |
//|    start  : start of the move (e.g., low of W1)                  |
//|    end    : end   of the move (e.g., high of W1)                 |
//|    ratio  : retracement ratio from `end` back toward `start`     |
//+------------------------------------------------------------------+
double EwbRetracement(const double start_price, const double end_price, const double ratio)
{
   return end_price - (end_price - start_price) * ratio;
}

//+------------------------------------------------------------------+
//|  Returns the price level of an extension of `ratio` from a base. |
//|    start  : start of the prior move                              |
//|    end    : end of the prior move                                |
//|    base   : the launch point from which the extension is         |
//|             projected (e.g., end of W2)                          |
//|    ratio  : extension ratio of the (end-start) leg               |
//+------------------------------------------------------------------+
double EwbExtension(const double start_price, const double end_price, const double base, const double ratio)
{
   return base + (end_price - start_price) * ratio;
}

//+------------------------------------------------------------------+
//|  Distance between two prices, always positive.                  |
//+------------------------------------------------------------------+
double EwbDistance(const double a, const double b)
{
   return MathAbs(a - b);
}

//+------------------------------------------------------------------+
//|  Returns the actual retracement ratio achieved between two       |
//|  pivots. Useful to score how cleanly a wave matches a Fibonacci  |
//|  tendency.                                                       |
//+------------------------------------------------------------------+
double EwbRetracementRatio(const double start_price, const double end_price, const double current)
{
   double range = MathAbs(end_price - start_price);
   if(range <= 0.0) return 0.0;
   return MathAbs(end_price - current) / range;
}

//+------------------------------------------------------------------+
//|  Returns the extension ratio of a move (`baseStart`->`baseEnd`)  |
//|  compared to a reference move (`refStart`->`refEnd`).            |
//+------------------------------------------------------------------+
double EwbExtensionRatio(const double refStart, const double refEnd, const double baseStart, const double baseEnd)
{
   double refLen  = MathAbs(refEnd  - refStart);
   double baseLen = MathAbs(baseEnd - baseStart);
   if(refLen <= 0.0) return 0.0;
   return baseLen / refLen;
}

//+------------------------------------------------------------------+
//|  Score how close `value` is to `target` within `tolerance`       |
//|  (0..1). Returns 1.0 for a perfect match, decreasing linearly to |
//|  0.0 at the edge of the tolerance band, clamped beyond that.     |
//+------------------------------------------------------------------+
double EwbProximityScore(const double value, const double target, const double tolerance)
{
   if(tolerance <= 0.0) return (value == target) ? 1.0 : 0.0;
   double diff = MathAbs(value - target) / tolerance;
   if(diff >= 1.0) return 0.0;
   return 1.0 - diff;
}

//+------------------------------------------------------------------+
//|  Best-of-many proximity score: matches `value` to the closest of |
//|  several targets.                                                |
//+------------------------------------------------------------------+
double EwbBestProximityScore(const double value, const double &targets[], const double tolerance)
{
   double best = 0.0;
   int n = ArraySize(targets);
   for(int i = 0; i < n; ++i)
   {
      double s = EwbProximityScore(value, targets[i], tolerance);
      if(s > best) best = s;
   }
   return best;
}

#endif // __EWB_FIBO_RATIOS_MQH__
