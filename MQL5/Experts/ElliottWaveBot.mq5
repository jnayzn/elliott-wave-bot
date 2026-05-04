//+------------------------------------------------------------------+
//|                                              ElliottWaveBot.mq5  |
//|             Professional Elliott Wave Expert Advisor for MT5     |
//|             Single-file build (no external .mqh dependencies)    |
//+------------------------------------------------------------------+
//|  Implements the strict rules of the Elliott Wave Principle as    |
//|  described in Frost & Prechter's reference book of the same      |
//|  name. The bot:                                                  |
//|    - Detects swing pivots with a self-contained ZigZag.          |
//|    - Identifies the most recent 5-wave impulse and (optional)    |
//|      ABC corrective sequence from those pivots.                  |
//|    - Validates the three Cardinal Rules (R1, R2, R3) on every    |
//|      candidate count and aborts trade entries when they fail.    |
//|    - Scores Fibonacci guideline matches into a 0-100 confidence. |
//|    - Builds Entry / SL / TP1 / TP2 / TP3 levels with R/R for     |
//|      either a "Wave 4 -> Wave 5" continuation or an "End of C    |
//|      -> new impulse" reversal.                                   |
//|    - Sizes positions by % of balance.                            |
//|    - Renders an on-chart HUD panel + numbered wave labels +      |
//|      Entry/SL/TP horizontal lines.                               |
//+------------------------------------------------------------------+
#property copyright "Elliott Wave Bot"
#property link      "https://github.com/jnayzn/elliott-wave-bot"
#property version   "1.10"
#property strict
#property description "Professional Elliott Wave EA - single-file build"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

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

//============================ CONSTANTS ============================
#define EWB_PREFIX        "EWB_"

#define EWB_FIBO_236   0.236
#define EWB_FIBO_382   0.382
#define EWB_FIBO_500   0.500
#define EWB_FIBO_618   0.618
#define EWB_FIBO_786   0.786
#define EWB_FIBO_1000  1.000
#define EWB_FIBO_1272  1.272
#define EWB_FIBO_1618  1.618
#define EWB_FIBO_2000  2.000
#define EWB_FIBO_2618  2.618
#define EWB_FIBO_4236  4.236

//============================== ENUMS ==============================
enum EwbPivotType
{
   EWB_PIVOT_NONE = 0,
   EWB_PIVOT_HIGH = 1,
   EWB_PIVOT_LOW  = -1
};

enum EwbWaveDirection
{
   EWB_WAVE_DIR_NONE     = 0,
   EWB_WAVE_DIR_BULLISH  = 1,
   EWB_WAVE_DIR_BEARISH  = -1
};

enum EwbWaveStatus
{
   EWB_WAVE_STATUS_NONE          = 0,
   EWB_WAVE_STATUS_DEVELOPING    = 1,
   EWB_WAVE_STATUS_IMPULSE_DONE  = 2,
   EWB_WAVE_STATUS_ABC_FORMING   = 3,
   EWB_WAVE_STATUS_ABC_COMPLETE  = 4
};

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

//============================= STRUCTS =============================
struct EwbPivot
{
   datetime      time;
   double        price;
   int           bar;
   EwbPivotType  type;
};

struct EwbWaveCount
{
   EwbWaveDirection direction;
   EwbWaveStatus    status;
   EwbPivot         p0;
   EwbPivot         p1;
   EwbPivot         p2;
   EwbPivot         p3;
   EwbPivot         p4;
   EwbPivot         p5;
   EwbPivot         pA;
   EwbPivot         pB;
   EwbPivot         pC;
   bool             rule_w2_no_full_retrace;
   bool             rule_w3_not_shortest;
   bool             rule_w4_no_overlap;
   bool             rule_w3_beyond_w1;
   bool             rule_w4_no_full_retrace;
   double           score_w2_retrace;
   double           score_w3_extension;
   double           score_w4_retrace;
   double           score_w5_projection;
   double           score_alternation;
   int              confidence;
   EwbWaveDirection bias;
   string           note;
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
   double       rr;
   bool         valid;
   string       label;
};

//============================ GLOBAL STATE =========================
CTrade          g_trade;
CPositionInfo   g_pos;

EwbWaveCount    g_wc;
EwbTradeSetup   g_setup;
EwbPivot        g_pivots[];

datetime        g_last_bar_time = 0;

// HUD palette / layout (initialised in OnInit).
int    g_hud_x;
int    g_hud_y;
int    g_hud_width   = 360;
int    g_hud_lh      = 16;
int    g_hud_font    = 9;
string g_hud_fontname = "Consolas";

color  g_clr_bg          = clrBlack;
color  g_clr_header_bg   = (color)C'40,40,40';
color  g_clr_header_txt  = clrYellow;
color  g_clr_label       = clrSilver;
color  g_clr_value       = clrWhite;
color  g_clr_good        = clrLime;
color  g_clr_bad         = clrRed;
color  g_clr_warn        = clrGold;
color  g_clr_impulse     = clrDodgerBlue;
color  g_clr_correction  = clrMediumPurple;
color  g_clr_entry       = clrGold;
color  g_clr_sl          = clrCrimson;
color  g_clr_tp          = clrLime;

//==================================================================+
//                       FIBONACCI HELPERS                           |
//==================================================================+
double EwbRetracement(const double s, const double e, const double r)
{
   return e - (e - s) * r;
}

double EwbExtension(const double s, const double e, const double base, const double r)
{
   return base + (e - s) * r;
}

double EwbRetracementRatio(const double s, const double e, const double cur)
{
   double range = MathAbs(e - s);
   if(range <= 0.0) return 0.0;
   return MathAbs(e - cur) / range;
}

double EwbProximityScore(const double value, const double target, const double tol)
{
   if(tol <= 0.0) return (value == target) ? 1.0 : 0.0;
   double diff = MathAbs(value - target) / tol;
   if(diff >= 1.0) return 0.0;
   return 1.0 - diff;
}

double EwbBestProximityScore3(const double v, const double t1, const double t2, const double t3, const double tol)
{
   double best = EwbProximityScore(v, t1, tol);
   double s2   = EwbProximityScore(v, t2, tol);
   double s3   = EwbProximityScore(v, t3, tol);
   if(s2 > best) best = s2;
   if(s3 > best) best = s3;
   return best;
}

//==================================================================+
//                       ZIGZAG PIVOT DETECTOR                       |
//==================================================================+
int EwbDetectPivots(const double &high[],
                    const double &low[],
                    const datetime &time[],
                    const int rates_total,
                    const int depth,
                    const int deviation,
                    const int backstep,
                    const double point_size,
                    const int max_pivots,
                    EwbPivot &out_pivots[])
{
   ArrayResize(out_pivots, 0);
   if(rates_total < depth * 2 + 10) return 0;

   double zz_high[];
   double zz_low[];
   ArrayResize(zz_high, rates_total);
   ArrayResize(zz_low,  rates_total);
   ArrayInitialize(zz_high, 0.0);
   ArrayInitialize(zz_low,  0.0);

   double last_high = 0.0;
   double last_low  = 0.0;

   // Pass 1 - local extrema
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

   // Pass 2 - alternation enforcement
   EwbPivot raw[];
   ArrayResize(raw, 0);

   int    last_type  = 0;
   double last_price = 0.0;
   int    last_bar   = -10000;

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
               last_bar   = i;
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
               last_bar   = i;
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
   int keep  = total < max_pivots ? total : max_pivots;
   ArrayResize(out_pivots, keep);
   for(int j = 0; j < keep; ++j)
      out_pivots[j] = raw[total - keep + j];
   return keep;
}

//==================================================================+
//                       WAVE COUNTER                                |
//==================================================================+
bool EwbIsBullishImpulse(const EwbPivot &p0, const EwbPivot &p1, const EwbPivot &p2,
                         const EwbPivot &p3, const EwbPivot &p4, const EwbPivot &p5)
{
   return p0.type == EWB_PIVOT_LOW  && p1.type == EWB_PIVOT_HIGH &&
          p2.type == EWB_PIVOT_LOW  && p3.type == EWB_PIVOT_HIGH &&
          p4.type == EWB_PIVOT_LOW  && p5.type == EWB_PIVOT_HIGH;
}

bool EwbIsBearishImpulse(const EwbPivot &p0, const EwbPivot &p1, const EwbPivot &p2,
                         const EwbPivot &p3, const EwbPivot &p4, const EwbPivot &p5)
{
   return p0.type == EWB_PIVOT_HIGH && p1.type == EWB_PIVOT_LOW  &&
          p2.type == EWB_PIVOT_HIGH && p3.type == EWB_PIVOT_LOW  &&
          p4.type == EWB_PIVOT_HIGH && p5.type == EWB_PIVOT_LOW;
}

void EwbInitWaveCount(EwbWaveCount &wc)
{
   wc.direction = EWB_WAVE_DIR_NONE;
   wc.status    = EWB_WAVE_STATUS_NONE;
   wc.bias      = EWB_WAVE_DIR_NONE;
   wc.note      = "";
   wc.rule_w2_no_full_retrace = false;
   wc.rule_w3_not_shortest    = false;
   wc.rule_w4_no_overlap      = false;
   wc.rule_w3_beyond_w1       = false;
   wc.rule_w4_no_full_retrace = false;
   wc.score_w2_retrace    = 0.0;
   wc.score_w3_extension  = 0.0;
   wc.score_w4_retrace    = 0.0;
   wc.score_w5_projection = 0.0;
   wc.score_alternation   = 0.0;
   wc.confidence = 0;
}

void EwbValidateCardinalRules(EwbWaveCount &wc)
{
   if(wc.direction == EWB_WAVE_DIR_NONE) return;

   double w1_start = wc.p0.price;
   double w1_end   = wc.p1.price;
   double w2_end   = wc.p2.price;
   double w3_end   = wc.p3.price;
   double w4_end   = wc.p4.price;
   double w5_end   = wc.p5.price;

   double len_w1 = MathAbs(w1_end - w1_start);
   double len_w3 = MathAbs(w3_end - w2_end);
   double len_w5 = (wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
                    ? MathAbs(w5_end - w4_end) : 0.0;

   // R1: W2 never retraces > 100% of W1
   if(wc.direction == EWB_WAVE_DIR_BULLISH)
      wc.rule_w2_no_full_retrace = (w2_end > w1_start);
   else
      wc.rule_w2_no_full_retrace = (w2_end < w1_start);

   // R3: W4 does not enter W1 territory
   if(wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
   {
      if(wc.direction == EWB_WAVE_DIR_BULLISH)
         wc.rule_w4_no_overlap = (w4_end > w1_end);
      else
         wc.rule_w4_no_overlap = (w4_end < w1_end);
   }
   else
   {
      wc.rule_w4_no_overlap = true;
   }

   // bonus: W4 never retraces > 100% of W3
   if(wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
   {
      if(wc.direction == EWB_WAVE_DIR_BULLISH)
         wc.rule_w4_no_full_retrace = (w4_end > w2_end);
      else
         wc.rule_w4_no_full_retrace = (w4_end < w2_end);
   }
   else
   {
      wc.rule_w4_no_full_retrace = true;
   }

   // bonus: W3 always travels beyond end of W1
   if(wc.direction == EWB_WAVE_DIR_BULLISH)
      wc.rule_w3_beyond_w1 = (w3_end > w1_end);
   else
      wc.rule_w3_beyond_w1 = (w3_end < w1_end);

   // R2: W3 never the shortest of W1/W3/W5
   if(wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
      wc.rule_w3_not_shortest = (len_w3 >= len_w1) && (len_w3 >= len_w5);
   else
      wc.rule_w3_not_shortest = (len_w3 >= len_w1);
}

void EwbScoreFibonacciGuidelines(EwbWaveCount &wc)
{
   double w1_start = wc.p0.price;
   double w1_end   = wc.p1.price;
   double w2_end   = wc.p2.price;
   double w3_end   = wc.p3.price;
   double w4_end   = wc.p4.price;
   double w5_end   = wc.p5.price;

   double len_w1 = MathAbs(w1_end - w1_start);
   double len_w3 = MathAbs(w3_end - w2_end);
   double len_w5 = (wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
                    ? MathAbs(w5_end - w4_end) : 0.0;

   if(len_w1 <= 0.0) { wc.confidence = 0; return; }

   // W2 retracement of W1 - sharp (.500 / .618 / .786)
   double w2_ratio = EwbRetracementRatio(w1_start, w1_end, w2_end);
   wc.score_w2_retrace = EwbBestProximityScore3(w2_ratio,
                          EWB_FIBO_500, EWB_FIBO_618, EWB_FIBO_786, 0.10);

   // W3 extension - 1.618 / 2.618 / 1.000
   double w3_ratio = len_w3 / len_w1;
   wc.score_w3_extension = EwbBestProximityScore3(w3_ratio,
                            EWB_FIBO_1618, EWB_FIBO_2618, EWB_FIBO_1000, 0.30);

   // W4 retracement of W3 - sideways (.382 / .236 / .500)
   if(len_w3 > 0.0 && wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
   {
      double w4_ratio = MathAbs(w3_end - w4_end) / len_w3;
      wc.score_w4_retrace = EwbBestProximityScore3(w4_ratio,
                              EWB_FIBO_382, EWB_FIBO_236, EWB_FIBO_500, 0.10);
   }

   // W5 projection - 1.000 / 0.618 / 1.618 of W1
   if(len_w5 > 0.0 && len_w1 > 0.0 && wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
   {
      double w5_ratio = len_w5 / len_w1;
      wc.score_w5_projection = EwbBestProximityScore3(w5_ratio,
                                 EWB_FIBO_1000, EWB_FIBO_618, EWB_FIBO_1618, 0.30);
   }

   // alternation
   if(wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE && len_w3 > 0.0)
   {
      double w2_r = w2_ratio;
      double w4_r = MathAbs(w3_end - w4_end) / len_w3;
      bool w2_sharp    = (w2_r >= 0.500);
      bool w4_sideways = (w4_r <= 0.382);
      bool w2_side     = (w2_r <  0.500);
      bool w4_sharp    = (w4_r >  0.382);
      wc.score_alternation = ((w2_sharp && w4_sideways) || (w2_side && w4_sharp)) ? 1.0 : 0.3;
   }

   // aggregate confidence
   int rule_pts = 0;
   if(wc.rule_w2_no_full_retrace) rule_pts += 15;
   if(wc.rule_w3_not_shortest)    rule_pts += 15;
   if(wc.rule_w4_no_overlap)      rule_pts += 15;
   if(wc.rule_w3_beyond_w1)       rule_pts += 8;
   if(wc.rule_w4_no_full_retrace) rule_pts += 7;

   double guide_pts = 0.0;
   guide_pts += 8.0  * wc.score_w2_retrace;
   guide_pts += 12.0 * wc.score_w3_extension;
   guide_pts += 8.0  * wc.score_w4_retrace;
   guide_pts += 8.0  * wc.score_w5_projection;
   guide_pts += 4.0  * wc.score_alternation;

   int total = rule_pts + (int)MathRound(guide_pts);
   if(total < 0)   total = 0;
   if(total > 100) total = 100;
   wc.confidence = total;

   if(!wc.rule_w2_no_full_retrace || !wc.rule_w3_not_shortest || !wc.rule_w4_no_overlap)
   {
      if(wc.confidence > 30) wc.confidence = 30;
   }
}

void EwbTagNote(EwbWaveCount &wc)
{
   switch(wc.status)
   {
      case EWB_WAVE_STATUS_DEVELOPING:   wc.note = "Impulse forming - watch for clean W3"; break;
      case EWB_WAVE_STATUS_IMPULSE_DONE: wc.note = "Trend maturity - watch for reversal";  break;
      case EWB_WAVE_STATUS_ABC_FORMING:  wc.note = "ABC correction in progress";           break;
      case EWB_WAVE_STATUS_ABC_COMPLETE: wc.note = "ABC complete - new impulse possible";  break;
      default:                           wc.note = "No clean Elliott count detected";      break;
   }
}

bool EwbAnalyseWaves(const EwbPivot &pivots[], EwbWaveCount &wc)
{
   EwbInitWaveCount(wc);
   int n = ArraySize(pivots);
   if(n < 4) return false;

   // 1) ABC complete (9 pivots)
   if(n >= 9)
   {
      EwbPivot p0 = pivots[n-9];
      EwbPivot p1 = pivots[n-8];
      EwbPivot p2 = pivots[n-7];
      EwbPivot p3 = pivots[n-6];
      EwbPivot p4 = pivots[n-5];
      EwbPivot p5 = pivots[n-4];
      EwbPivot pA = pivots[n-3];
      EwbPivot pB = pivots[n-2];
      EwbPivot pC = pivots[n-1];

      bool bull = EwbIsBullishImpulse(p0, p1, p2, p3, p4, p5);
      bool bear = EwbIsBearishImpulse(p0, p1, p2, p3, p4, p5);
      if(bull || bear)
      {
         wc.direction = bull ? EWB_WAVE_DIR_BULLISH : EWB_WAVE_DIR_BEARISH;
         wc.status    = EWB_WAVE_STATUS_ABC_COMPLETE;
         wc.p0 = p0; wc.p1 = p1; wc.p2 = p2; wc.p3 = p3; wc.p4 = p4; wc.p5 = p5;
         wc.pA = pA; wc.pB = pB; wc.pC = pC;
         wc.bias = wc.direction;

         EwbValidateCardinalRules(wc);
         EwbScoreFibonacciGuidelines(wc);
         EwbTagNote(wc);
         if(wc.rule_w2_no_full_retrace && wc.rule_w3_not_shortest &&
            wc.rule_w4_no_overlap && wc.rule_w3_beyond_w1)
            return true;
         EwbInitWaveCount(wc);
      }
   }

   // 2) Impulse done (6 pivots)
   if(n >= 6)
   {
      EwbPivot p0 = pivots[n-6];
      EwbPivot p1 = pivots[n-5];
      EwbPivot p2 = pivots[n-4];
      EwbPivot p3 = pivots[n-3];
      EwbPivot p4 = pivots[n-2];
      EwbPivot p5 = pivots[n-1];

      bool bull = EwbIsBullishImpulse(p0, p1, p2, p3, p4, p5);
      bool bear = EwbIsBearishImpulse(p0, p1, p2, p3, p4, p5);
      if(bull || bear)
      {
         wc.direction = bull ? EWB_WAVE_DIR_BULLISH : EWB_WAVE_DIR_BEARISH;
         wc.status    = EWB_WAVE_STATUS_IMPULSE_DONE;
         wc.p0 = p0; wc.p1 = p1; wc.p2 = p2; wc.p3 = p3; wc.p4 = p4; wc.p5 = p5;
         wc.bias = (wc.direction == EWB_WAVE_DIR_BULLISH) ? EWB_WAVE_DIR_BEARISH : EWB_WAVE_DIR_BULLISH;

         EwbValidateCardinalRules(wc);
         EwbScoreFibonacciGuidelines(wc);
         EwbTagNote(wc);
         if(wc.rule_w2_no_full_retrace && wc.rule_w3_not_shortest &&
            wc.rule_w4_no_overlap && wc.rule_w3_beyond_w1)
            return true;
         EwbInitWaveCount(wc);
      }
   }

   // 3) Developing (4 pivots)
   if(n >= 4)
   {
      EwbPivot p0 = pivots[n-4];
      EwbPivot p1 = pivots[n-3];
      EwbPivot p2 = pivots[n-2];
      EwbPivot p3 = pivots[n-1];

      bool bull = (p0.type == EWB_PIVOT_LOW  && p1.type == EWB_PIVOT_HIGH &&
                   p2.type == EWB_PIVOT_LOW  && p3.type == EWB_PIVOT_HIGH);
      bool bear = (p0.type == EWB_PIVOT_HIGH && p1.type == EWB_PIVOT_LOW  &&
                   p2.type == EWB_PIVOT_HIGH && p3.type == EWB_PIVOT_LOW);
      if(bull || bear)
      {
         wc.direction = bull ? EWB_WAVE_DIR_BULLISH : EWB_WAVE_DIR_BEARISH;
         wc.status    = EWB_WAVE_STATUS_DEVELOPING;
         wc.p0 = p0; wc.p1 = p1; wc.p2 = p2; wc.p3 = p3;
         wc.bias = wc.direction;

         EwbValidateCardinalRules(wc);
         EwbScoreFibonacciGuidelines(wc);
         EwbTagNote(wc);
         return wc.rule_w2_no_full_retrace && wc.rule_w3_beyond_w1;
      }
   }

   EwbTagNote(wc);
   return false;
}

//==================================================================+
//                       TRADE SETUP BUILDERS                        |
//==================================================================+
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

bool EwbBuildW4toW5Setup(const EwbWaveCount &wc, const double sl_buf_pts,
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
   double buf      = sl_buf_pts * point_size;

   ts.kind  = EWB_SETUP_W4_TO_W5;
   ts.label = "W4 -> W5 continuation";

   if(wc.direction == EWB_WAVE_DIR_BULLISH)
   {
      ts.side  = EWB_SETUP_SIDE_BUY;
      ts.entry = w3_end;
      ts.sl    = w1_end - buf;
      ts.tp1   = w4_end + len_w1 * EWB_FIBO_1000;
      ts.tp2   = w4_end + len_w1 * EWB_FIBO_1618;
      ts.tp3   = w4_end + len_w1 * EWB_FIBO_2618;
   }
   else
   {
      ts.side  = EWB_SETUP_SIDE_SELL;
      ts.entry = w3_end;
      ts.sl    = w1_end + buf;
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

bool EwbBuildEndOfCSetup(const EwbWaveCount &wc, const double sl_buf_pts,
                         const double point_size, EwbTradeSetup &ts)
{
   EwbInitTradeSetup(ts);
   if(wc.status != EWB_WAVE_STATUS_ABC_COMPLETE) return false;

   double w0   = wc.p0.price;
   double w5   = wc.p5.price;
   double pc   = wc.pC.price;
   double len5 = MathAbs(w5 - w0);
   if(len5 <= 0.0) return false;

   ts.kind  = EWB_SETUP_END_OF_C;
   ts.label = "End of C -> new impulse";

   double buf = sl_buf_pts * point_size;

   if(wc.bias == EWB_WAVE_DIR_BULLISH)
   {
      ts.side  = EWB_SETUP_SIDE_BUY;
      ts.entry = pc;
      ts.sl    = pc - buf;
      ts.tp1   = pc + len5 * EWB_FIBO_382;
      ts.tp2   = pc + len5 * EWB_FIBO_618;
      ts.tp3   = pc + len5 * EWB_FIBO_1000;
   }
   else if(wc.bias == EWB_WAVE_DIR_BEARISH)
   {
      ts.side  = EWB_SETUP_SIDE_SELL;
      ts.entry = pc;
      ts.sl    = pc + buf;
      ts.tp1   = pc - len5 * EWB_FIBO_382;
      ts.tp2   = pc - len5 * EWB_FIBO_618;
      ts.tp3   = pc - len5 * EWB_FIBO_1000;
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

//==================================================================+
//                       RISK MANAGER                                |
//==================================================================+
double EwbComputeLotSize(const double balance,
                         const double risk_percent,
                         const double sl_distance,
                         const double tick_value,
                         const double tick_size,
                         const double vol_min,
                         const double vol_max,
                         const double vol_step)
{
   if(balance <= 0.0 || risk_percent <= 0.0) return 0.0;
   if(sl_distance <= 0.0 || tick_value <= 0.0 || tick_size <= 0.0) return 0.0;

   double risk_money = balance * (risk_percent / 100.0);
   double money_per_lot_per_point = tick_value / tick_size;
   double lots = risk_money / (sl_distance * money_per_lot_per_point);

   if(lots < vol_min) lots = vol_min;
   if(lots > vol_max) lots = vol_max;

   if(vol_step > 0.0)
   {
      double steps = MathFloor(lots / vol_step);
      lots = steps * vol_step;
   }
   if(lots < vol_min) lots = vol_min;
   return lots;
}

//==================================================================+
//                       HUD OBJECT HELPERS                          |
//==================================================================+
void EwbEnsureLabel(const string name, const int x, const int y,
                    const string text, const color clr, const int font_size = 0)
{
   int fsz = (font_size > 0) ? font_size : g_hud_font;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fsz);
   ObjectSetString (0, name, OBJPROP_FONT, g_hud_fontname);
}

void EwbEnsureRectLabel(const string name, const int x, const int y,
                        const int width, const int height, const color bg)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, (color)C'80,80,80');
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
}

void EwbEnsureButton(const string name, const int x, const int y,
                     const int width, const int height,
                     const string text, const color bg, const color text_clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, (color)C'120,120,120');
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, g_hud_font);
      ObjectSetString (0, name, OBJPROP_FONT, g_hud_fontname);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_clr);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
}

void EwbEnsureChartText(const string name, const datetime t, const double price,
                        const string text, const color clr,
                        const ENUM_ANCHOR_POINT anchor)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME,  t);
   ObjectSetDouble (0, name, OBJPROP_PRICE, price);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, g_hud_font + 2);
   ObjectSetString (0, name, OBJPROP_FONT, g_hud_fontname);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
}

void EwbEnsureTrendLine(const string name, const datetime t1, const double p1,
                        const datetime t2, const double p2, const color clr,
                        const int width, const ENUM_LINE_STYLE style = STYLE_SOLID)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
}

void EwbEnsureHLine(const string name, const double price, const color clr,
                    const int width, const ENUM_LINE_STYLE style = STYLE_DASHDOT)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   ObjectSetDouble (0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
}

void EwbDestroyAll(const string prefix)
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

//==================================================================+
//                       HUD RENDER                                  |
//==================================================================+
string EwbDirText(const EwbWaveDirection d)
{
   if(d == EWB_WAVE_DIR_BULLISH) return "BULLISH";
   if(d == EWB_WAVE_DIR_BEARISH) return "BEARISH";
   return "-";
}

color EwbDirColor(const EwbWaveDirection d)
{
   if(d == EWB_WAVE_DIR_BULLISH) return g_clr_good;
   if(d == EWB_WAVE_DIR_BEARISH) return g_clr_bad;
   return g_clr_label;
}

string EwbStatusText(const EwbWaveStatus s)
{
   switch(s)
   {
      case EWB_WAVE_STATUS_DEVELOPING:   return "Developing";
      case EWB_WAVE_STATUS_IMPULSE_DONE: return "Complete";
      case EWB_WAVE_STATUS_ABC_FORMING:  return "ABC forming";
      case EWB_WAVE_STATUS_ABC_COMPLETE: return "Complete";
   }
   return "No count";
}

string EwbTfText(const ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
   }
   return "?";
}

void EwbRenderPanel(const string symbol,
                    const ENUM_TIMEFRAMES tf,
                    const datetime updated,
                    const EwbWaveCount &wc,
                    const EwbTradeSetup &ts)
{
   const int x  = g_hud_x;
   const int y  = g_hud_y;
   const int w  = g_hud_width;
   const int lh = g_hud_lh;
   const string p = EWB_PREFIX;

   EwbEnsureRectLabel(p + "bg",     x, y, w, lh * 22 + 10, g_clr_bg);
   EwbEnsureRectLabel(p + "header", x, y, w - 70, lh + 6, g_clr_header_bg);
   EwbEnsureLabel    (p + "title",  x + 8, y + 4, "Elliott Wave Analyzer", g_clr_header_txt, g_hud_font + 1);
   EwbEnsureButton   (p + "sync_btn", x + w - 60, y + 2, 56, lh + 2, "SYNC", clrGoldenrod, clrBlack);

   int row = y + lh + 12;

   EwbEnsureLabel(p + "lab_sym", x + 8,  row, "Symbol:",   g_clr_label);
   EwbEnsureLabel(p + "val_sym", x + 90, row, symbol,      g_clr_value);
   row += lh;

   EwbEnsureLabel(p + "lab_tf",  x + 8,  row, "Timeframe:", g_clr_label);
   EwbEnsureLabel(p + "val_tf",  x + 90, row, EwbTfText(tf), g_clr_value);
   row += lh;

   EwbEnsureLabel(p + "lab_upd", x + 8,  row, "Updated:",  g_clr_label);
   EwbEnsureLabel(p + "val_upd", x + 90, row,
                  TimeToString(updated, TIME_DATE | TIME_MINUTES), g_clr_value);
   row += lh;

   EwbEnsureLabel(p + "lab_st",  x + 8,  row, "Status:",   g_clr_label);
   EwbEnsureLabel(p + "val_st",  x + 90, row, EwbStatusText(wc.status), g_clr_value);
   row += lh + 4;

   EwbEnsureLabel(p + "wc_hdr",  x + 8,  row, "WAVE COUNT", g_clr_warn);
   row += lh;

   EwbEnsureLabel(p + "lab_note", x + 16, row, wc.note, g_clr_value);
   row += lh;

   EwbEnsureLabel(p + "lab_dir", x + 16,  row, "Direction:",  g_clr_label);
   EwbEnsureLabel(p + "val_dir", x + 110, row, EwbDirText(wc.direction), EwbDirColor(wc.direction));
   row += lh;

   string bar = "";
   int filled = (int)MathRound(wc.confidence / 10.0);
   if(filled < 0)  filled = 0;
   if(filled > 10) filled = 10;
   for(int i = 0; i < 10; ++i) bar += (i < filled ? "#" : "-");
   color cf_clr = (wc.confidence >= 70 ? g_clr_good :
                   wc.confidence >= 40 ? g_clr_warn : g_clr_bad);
   EwbEnsureLabel(p + "lab_cf",  x + 16,  row, "Confidence:", g_clr_label);
   EwbEnsureLabel(p + "val_cf",  x + 110, row,
                  StringFormat("[%s] %d/100", bar, wc.confidence), cf_clr);
   row += lh;

   EwbEnsureLabel(p + "lab_bias", x + 16,  row, "Bias:", g_clr_label);
   EwbEnsureLabel(p + "val_bias", x + 110, row, EwbDirText(wc.bias), EwbDirColor(wc.bias));
   row += lh + 4;

   EwbEnsureLabel(p + "ts_hdr", x + 8, row, "TRADE SETUP", g_clr_warn);
   row += lh;

   if(ts.valid)
   {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      EwbEnsureLabel(p + "lab_e",  x + 16,  row, "Entry:", g_clr_label);
      EwbEnsureLabel(p + "val_e",  x + 110, row, DoubleToString(ts.entry, digits), g_clr_entry);
      row += lh;
      EwbEnsureLabel(p + "lab_sl", x + 16,  row, "SL:", g_clr_label);
      EwbEnsureLabel(p + "val_sl", x + 110, row, DoubleToString(ts.sl, digits), g_clr_sl);
      row += lh;
      EwbEnsureLabel(p + "lab_t1", x + 16,  row, "TP1:", g_clr_label);
      EwbEnsureLabel(p + "val_t1", x + 110, row, DoubleToString(ts.tp1, digits), g_clr_tp);
      row += lh;
      EwbEnsureLabel(p + "lab_t2", x + 16,  row, "TP2:", g_clr_label);
      EwbEnsureLabel(p + "val_t2", x + 110, row, DoubleToString(ts.tp2, digits), g_clr_tp);
      row += lh;
      EwbEnsureLabel(p + "lab_t3", x + 16,  row, "TP3:", g_clr_label);
      EwbEnsureLabel(p + "val_t3", x + 110, row, DoubleToString(ts.tp3, digits), g_clr_tp);
      row += lh;
      color rr_clr = (ts.rr >= 2.0 ? g_clr_good : ts.rr >= 1.0 ? g_clr_warn : g_clr_bad);
      EwbEnsureLabel(p + "lab_rr", x + 16,  row, "R/R:", g_clr_label);
      EwbEnsureLabel(p + "val_rr", x + 110, row, DoubleToString(ts.rr, 2), rr_clr);
   }
   else
   {
      EwbEnsureLabel(p + "lab_e", x + 16, row, "No setup", g_clr_label);
      // delete stale setup labels if a previous tick had a setup.
      ObjectDelete(0, p + "val_e");
      ObjectDelete(0, p + "lab_sl"); ObjectDelete(0, p + "val_sl");
      ObjectDelete(0, p + "lab_t1"); ObjectDelete(0, p + "val_t1");
      ObjectDelete(0, p + "lab_t2"); ObjectDelete(0, p + "val_t2");
      ObjectDelete(0, p + "lab_t3"); ObjectDelete(0, p + "val_t3");
      ObjectDelete(0, p + "lab_rr"); ObjectDelete(0, p + "val_rr");
      row += lh;
   }
   row += lh + 4;

   EwbEnsureLabel(p + "rule_hdr", x + 8, row, "ELLIOTT RULES", g_clr_warn);
   row += lh;

   EwbEnsureLabel(p + "lab_r1", x + 16,  row, "R1 W2<=W1:", g_clr_label);
   EwbEnsureLabel(p + "val_r1", x + 130, row,
                  wc.rule_w2_no_full_retrace ? "YES" : "NO",
                  wc.rule_w2_no_full_retrace ? g_clr_good : g_clr_bad);
   row += lh;

   EwbEnsureLabel(p + "lab_r2", x + 16,  row, "R2 W3 not short:", g_clr_label);
   EwbEnsureLabel(p + "val_r2", x + 130, row,
                  wc.rule_w3_not_shortest ? "YES" : "NO",
                  wc.rule_w3_not_shortest ? g_clr_good : g_clr_bad);
   row += lh;

   EwbEnsureLabel(p + "lab_r3", x + 16,  row, "R3 W4!=W1 zone:", g_clr_label);
   EwbEnsureLabel(p + "val_r3", x + 130, row,
                  wc.rule_w4_no_overlap ? "YES" : "NO",
                  wc.rule_w4_no_overlap ? g_clr_good : g_clr_bad);
   row += lh + 4;

   EwbEnsureLabel(p + "notes_hdr", x + 8, row, "NOTES", g_clr_warn);
}

void EwbRenderWaveOverlay(const EwbWaveCount &wc)
{
   const string p = EWB_PREFIX + "wv_";

   if(wc.direction != EWB_WAVE_DIR_NONE)
   {
      EwbEnsureTrendLine(p + "01", wc.p0.time, wc.p0.price, wc.p1.time, wc.p1.price, g_clr_impulse, 2);
      EwbEnsureTrendLine(p + "12", wc.p1.time, wc.p1.price, wc.p2.time, wc.p2.price, g_clr_impulse, 2);
      EwbEnsureTrendLine(p + "23", wc.p2.time, wc.p2.price, wc.p3.time, wc.p3.price, g_clr_impulse, 2);

      ENUM_ANCHOR_POINT a1 = (wc.direction == EWB_WAVE_DIR_BULLISH) ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER;
      ENUM_ANCHOR_POINT a2 = (wc.direction == EWB_WAVE_DIR_BULLISH) ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER;
      ENUM_ANCHOR_POINT a3 = a1;
      EwbEnsureChartText(p + "lbl1", wc.p1.time, wc.p1.price, "1", g_clr_impulse, a1);
      EwbEnsureChartText(p + "lbl2", wc.p2.time, wc.p2.price, "2", g_clr_impulse, a2);
      EwbEnsureChartText(p + "lbl3", wc.p3.time, wc.p3.price, "3", g_clr_impulse, a3);
   }
   if(wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
   {
      EwbEnsureTrendLine(p + "34", wc.p3.time, wc.p3.price, wc.p4.time, wc.p4.price, g_clr_impulse, 2);
      EwbEnsureTrendLine(p + "45", wc.p4.time, wc.p4.price, wc.p5.time, wc.p5.price, g_clr_impulse, 2);
      ENUM_ANCHOR_POINT a4 = (wc.direction == EWB_WAVE_DIR_BULLISH) ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER;
      ENUM_ANCHOR_POINT a5 = (wc.direction == EWB_WAVE_DIR_BULLISH) ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER;
      EwbEnsureChartText(p + "lbl4", wc.p4.time, wc.p4.price, "4", g_clr_impulse, a4);
      EwbEnsureChartText(p + "lbl5", wc.p5.time, wc.p5.price, "5", g_clr_impulse, a5);
   }
   if(wc.status >= EWB_WAVE_STATUS_ABC_FORMING)
   {
      EwbEnsureTrendLine(p + "5A", wc.p5.time, wc.p5.price, wc.pA.time, wc.pA.price, g_clr_correction, 2);
      ENUM_ANCHOR_POINT aA = (wc.direction == EWB_WAVE_DIR_BULLISH) ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER;
      EwbEnsureChartText(p + "lblA", wc.pA.time, wc.pA.price, "A", g_clr_correction, aA);
   }
   if(wc.status >= EWB_WAVE_STATUS_ABC_COMPLETE)
   {
      EwbEnsureTrendLine(p + "AB", wc.pA.time, wc.pA.price, wc.pB.time, wc.pB.price, g_clr_correction, 2);
      EwbEnsureTrendLine(p + "BC", wc.pB.time, wc.pB.price, wc.pC.time, wc.pC.price, g_clr_correction, 2);
      ENUM_ANCHOR_POINT aB = (wc.direction == EWB_WAVE_DIR_BULLISH) ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER;
      ENUM_ANCHOR_POINT aC = (wc.direction == EWB_WAVE_DIR_BULLISH) ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER;
      EwbEnsureChartText(p + "lblB", wc.pB.time, wc.pB.price, "B", g_clr_correction, aB);
      EwbEnsureChartText(p + "lblC", wc.pC.time, wc.pC.price, "C", g_clr_correction, aC);
   }
}

void EwbRenderTradeLines(const EwbTradeSetup &ts)
{
   const string p = EWB_PREFIX + "tl_";
   if(!ts.valid)
   {
      ObjectDelete(0, p + "entry");
      ObjectDelete(0, p + "sl");
      ObjectDelete(0, p + "tp1");
      ObjectDelete(0, p + "tp2");
      ObjectDelete(0, p + "tp3");
      return;
   }
   EwbEnsureHLine(p + "entry", ts.entry, g_clr_entry, 1, STYLE_DASHDOT);
   EwbEnsureHLine(p + "sl",    ts.sl,    g_clr_sl,    1, STYLE_DASH);
   EwbEnsureHLine(p + "tp1",   ts.tp1,   g_clr_tp,    1, STYLE_DASH);
   EwbEnsureHLine(p + "tp2",   ts.tp2,   g_clr_tp,    1, STYLE_DASH);
   EwbEnsureHLine(p + "tp3",   ts.tp3,   g_clr_tp,    1, STYLE_DASH);
}

//==================================================================+
//                       PIPELINE                                    |
//==================================================================+
bool RecomputeAnalysis()
{
   int avail = Bars(_Symbol, _Period);
   int look  = (InpHistoryBars < avail) ? InpHistoryBars : avail;
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
      EwbTradeSetup ts_c;
      EwbTradeSetup ts_w;
      bool has_c = InpAllowEndOfC && EwbBuildEndOfCSetup(g_wc, InpSLBufferPoints, point, ts_c);
      bool has_w = InpAllowW4ToW5 && EwbBuildW4toW5Setup(g_wc, InpSLBufferPoints, point, ts_w);

      if(has_c && has_w)
      {
         if(ts_c.rr >= ts_w.rr) g_setup = ts_c;
         else                    g_setup = ts_w;
      }
      else if(has_c) g_setup = ts_c;
      else if(has_w) g_setup = ts_w;
   }
   return ok;
}

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

   double dist_to_entry = MathAbs(price_now - g_setup.entry);
   double atr_proxy     = MathAbs(g_setup.tp1 - g_setup.entry);
   if(atr_proxy > 0.0 && dist_to_entry > atr_proxy)
      return;

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

void RenderAll()
{
   if(!InpShowHUD)
   {
      EwbDestroyAll(EWB_PREFIX);
      return;
   }
   EwbRenderPanel(_Symbol, _Period, TimeCurrent(), g_wc, g_setup);
   EwbRenderWaveOverlay(g_wc);
   EwbRenderTradeLines(g_setup);
   ChartRedraw();
}

//==================================================================+
//                       EXPERT EVENT HANDLERS                       |
//==================================================================+
int OnInit()
{
   g_hud_x = InpHUDX;
   g_hud_y = InpHUDY;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);

   EwbDestroyAll(EWB_PREFIX);
   RecomputeAnalysis();
   RenderAll();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EwbDestroyAll(EWB_PREFIX);
   ChartRedraw();
}

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
      EwbEnsureLabel(EWB_PREFIX + "val_upd",
                     g_hud_x + 90,
                     g_hud_y + g_hud_lh + 12 + g_hud_lh * 2,
                     TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
                     g_clr_value);
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      string sync_name = EWB_PREFIX + "sync_btn";
      if(sparam == sync_name)
      {
         RecomputeAnalysis();
         RenderAll();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
   }
}

//+------------------------------------------------------------------+
