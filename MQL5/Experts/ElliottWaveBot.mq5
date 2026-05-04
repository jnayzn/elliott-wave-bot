//+------------------------------------------------------------------+
//|                                              ElliottWaveBot.mq5  |
//|             Professional Elliott Wave Expert Advisor for MT5     |
//|             Single-file build (no external .mqh dependencies)    |
//+------------------------------------------------------------------+
//|  Local, open-source Elliott Wave analyzer + EA. The visual       |
//|  layout (panel sections, wave-label conventions, color palette,  |
//|  trade-level lines) follows the structure described in the       |
//|  Enitrader Elliott Wave Analyzer User Manual v1.1, but the       |
//|  analysis runs entirely client-side - no external API calls,     |
//|  no license server, no subscription. The Elliott rules and       |
//|  Fibonacci guidelines applied are the canonical Frost & Prechter |
//|  set.                                                            |
//|                                                                  |
//|  The bot:                                                        |
//|    - Detects swing pivots with a self-contained ZigZag.          |
//|    - Searches recent pivots for the best-scoring 5-wave          |
//|      impulse + optional ABC correction.                          |
//|    - Validates the three Cardinal Rules (R1, R2, R3) and rejects |
//|      any count that breaks a hard rule.                          |
//|    - Scores Fibonacci-guideline alignment into a 0-100           |
//|      confidence value.                                           |
//|    - Builds Entry / SL / TP1 / TP2 / TP3 levels with R/R.        |
//|    - Optionally places market orders (off by default).           |
//|    - Renders a 340 px panel with header, info rows, wave count,  |
//|      trade setup, and status messages.                           |
//|    - Draws numbered wave labels (0..5, A, B, C) at pivots,       |
//|      color-coded trend lines per wave, and trade-level lines     |
//|      that span the chart with right-edge price tags.             |
//+------------------------------------------------------------------+
#property copyright "Elliott Wave Bot (open source)"
#property link      "https://github.com/jnayzn/elliott-wave-bot"
#property version   "1.20"
#property strict
#property description "Local Elliott Wave EA - panel + wave labels + trade levels"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//==================================================================+
//                       COLOR PALETTE                               |
//==================================================================+
// Hex values mirror the user-manual palette so the chart reads      |
// the same way as a typical Elliott Wave dashboard.                 |
#define EWB_C_W1            (color)C'74,158,255'    // #4A9EFF
#define EWB_C_W2            (color)C'217,155,58'    // #D99B3A
#define EWB_C_W3            (color)C'74,158,255'    // #4A9EFF
#define EWB_C_W4            (color)C'217,155,58'    // #D99B3A
#define EWB_C_W5            (color)C'34,197,94'     // #22C55E
#define EWB_C_ABC           (color)C'192,132,252'   // #C084FC

#define EWB_C_ENTRY         (color)C'34,197,94'     // #22C55E
#define EWB_C_SL            (color)C'239,68,68'     // #EF4444
#define EWB_C_TP1           (color)C'96,165,250'    // #60A5FA
#define EWB_C_TP2           (color)C'167,139,250'   // #A78BFA
#define EWB_C_TP3           (color)C'34,211,238'    // #22D3EE
#define EWB_C_FIB           (color)C'255,215,0'     // #FFD700

#define EWB_C_PANEL_BG      (color)C'42,42,42'      // #2A2A2A
#define EWB_C_PANEL_HEADER  (color)C'26,26,26'      // #1A1A1A
#define EWB_C_PANEL_BORDER  (color)C'80,80,80'
#define EWB_C_TITLE         (color)C'255,215,0'     // gold
#define EWB_C_LABEL         (color)C'156,163,175'   // muted gray
#define EWB_C_VALUE         clrWhite
#define EWB_C_HEADING       (color)C'217,155,58'    // amber section heading
#define EWB_C_BUY           (color)C'74,158,255'    // #4A9EFF
#define EWB_C_SELL          (color)C'255,74,74'     // #FF4A4A
#define EWB_C_GOOD          (color)C'34,197,94'
#define EWB_C_BAD           (color)C'239,68,68'
#define EWB_C_WARN          (color)C'251,191,36'    // amber warning

//==================================================================+
//                       INPUTS                                      |
//==================================================================+
input group "Analysis"
input int    InpBarsToAnalyze   = 800;     // Bars to analyze (500-2000)
input bool   InpAutoSyncOnNewBar = true;   // Re-run analysis on each new bar
input int    InpZZDepth         = 12;      // ZigZag Depth (bars)
input int    InpZZDeviation     = 5;       // ZigZag Deviation (points)
input int    InpZZBackstep      = 3;       // ZigZag Backstep (bars)
input int    InpMaxPivots       = 24;      // Max pivots to keep for search

input group "Elliott Rules"
input bool   InpRequireAllRules = true;    // Reject counts that break R1/R2/R3
input bool   InpAllowW4ToW5     = true;    // Enable W4 -> W5 continuation setup
input bool   InpAllowEndOfC     = true;    // Enable End-of-C reversal setup
input int    InpMinConfidence   = 60;      // Min confidence (0-100) to trade

input group "Wave Drawings"
input bool   InpDrawWaveLabels  = true;    // Draw 0,1,2,3,4,5,A,B,C labels
input bool   InpDrawTrendLines  = true;    // Draw lines between pivots
input int    InpLabelFontSize   = 11;      // Wave label font size
input ENUM_LINE_STYLE InpWaveLineStyle = STYLE_SOLID; // Wave line style
input int    InpWaveLineWidth   = 2;       // Wave line width (1-5)

input group "Trade Levels"
input bool   InpDrawEntry       = true;    // Show Entry line
input bool   InpDrawSL          = true;    // Show Stop Loss line
input bool   InpDrawTP1         = true;    // Show TP1 (conservative)
input bool   InpDrawTP2         = true;    // Show TP2 (primary)
input bool   InpDrawTP3         = true;    // Show TP3 (aggressive)
input ENUM_LINE_STYLE InpLevelStyle = STYLE_DASH; // Level line style
input int    InpLevelWidth      = 1;       // Level line width

input group "Fibonacci"
input bool   InpDrawFibLevels   = false;   // Draw Fibonacci retracement levels
input ENUM_LINE_STYLE InpFibStyle = STYLE_DOT; // Fib line style
input int    InpFibWidth        = 1;       // Fib line width

input group "Panel"
input int    InpPanelX          = 20;      // Panel X position (px)
input int    InpPanelY          = 30;      // Panel Y position (px)

input group "Trading (optional)"
input bool   InpAutoTrade       = false;   // Place market orders automatically
input double InpRiskPercent     = 1.0;     // Risk per trade (% balance)
input double InpMinRR           = 1.5;     // Minimum R/R to trade
input double InpSLBufferPoints  = 50;      // SL buffer beyond invalidation (points)
input int    InpMagic           = 730501;  // Magic number

//==================================================================+
//                       CONSTANTS                                   |
//==================================================================+
#define EWB_PFX             "EWB_"
#define EWB_PANEL_W         340
#define EWB_PANEL_LH        18
#define EWB_PANEL_FONT      9
#define EWB_PANEL_FONTNAME  "Consolas"

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

//==================================================================+
//                       ENUMS                                       |
//==================================================================+
enum EwbPivotType
{
   EWB_PIVOT_NONE = 0,
   EWB_PIVOT_HIGH = 1,
   EWB_PIVOT_LOW  = -1
};

enum EwbWaveDirection
{
   EWB_DIR_NONE     = 0,
   EWB_DIR_BULLISH  = 1,
   EWB_DIR_BEARISH  = -1
};

enum EwbWaveStatus
{
   EWB_ST_NONE          = 0,
   EWB_ST_W1_DONE       = 1,    // p0,p1 known
   EWB_ST_W2_DONE       = 2,    // p0..p2
   EWB_ST_W3_FORMING    = 3,    // p0..p2 + price moving in W3
   EWB_ST_W3_DONE       = 4,    // p0..p3
   EWB_ST_W4_DONE       = 5,    // p0..p4
   EWB_ST_W5_FORMING    = 6,    // p0..p4 + price moving in W5
   EWB_ST_W5_DONE       = 7,    // p0..p5
   EWB_ST_A_DONE        = 8,    // + pA
   EWB_ST_B_DONE        = 9,    // + pB
   EWB_ST_C_DONE        = 10    // + pC, sequence complete
};

enum EwbSetupKind
{
   EWB_SETUP_NONE     = 0,
   EWB_SETUP_W4_TO_W5 = 1,
   EWB_SETUP_END_OF_C = 2
};

enum EwbSetupSide
{
   EWB_SIDE_NONE = 0,
   EWB_SIDE_BUY  = 1,
   EWB_SIDE_SELL = -1
};

enum EwbRunState
{
   EWB_RUN_IDLE      = 0,
   EWB_RUN_ANALYZING = 1,
   EWB_RUN_RENDERING = 2,
   EWB_RUN_NEED_BARS = 3
};

//==================================================================+
//                       STRUCTS                                     |
//==================================================================+
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
   int              waves_found;            // 0..5 for impulse, +1..3 for ABC
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
   double           score_clarity;          // 0..1
   double           score_fib;              // 0..1
   double           score_rules;            // 0..1
   double           score_projection;       // 0..1
   int              confidence;             // 0..100
   EwbWaveDirection bias;
   string           position_text;          // e.g. "Wave 3 in progress"
   string           alt_text;               // alternative count note
   string           warnings;               // engine warnings
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

//==================================================================+
//                       GLOBAL STATE                                |
//==================================================================+
CTrade          g_trade;
CPositionInfo   g_pos;

EwbWaveCount    g_wc;
EwbTradeSetup   g_setup;
EwbPivot        g_pivots[];

datetime        g_last_bar_time = 0;
datetime        g_last_analysis = 0;
EwbRunState     g_state         = EWB_RUN_IDLE;

//==================================================================+
//                       FIBONACCI HELPERS                           |
//==================================================================+
double EwbProximity(const double v, const double target, const double tol)
{
   if(tol <= 0.0) return (v == target) ? 1.0 : 0.0;
   double d = MathAbs(v - target) / tol;
   if(d >= 1.0) return 0.0;
   return 1.0 - d;
}

double EwbBestProximity3(const double v, const double a, const double b, const double c, const double tol)
{
   double s1 = EwbProximity(v, a, tol);
   double s2 = EwbProximity(v, b, tol);
   double s3 = EwbProximity(v, c, tol);
   if(s2 > s1) s1 = s2;
   if(s3 > s1) s1 = s3;
   return s1;
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
                    EwbPivot &out[])
{
   ArrayResize(out, 0);
   if(rates_total < depth * 2 + 10) return 0;

   double zz_high[];
   double zz_low[];
   ArrayResize(zz_high, rates_total);
   ArrayResize(zz_low,  rates_total);
   ArrayInitialize(zz_high, 0.0);
   ArrayInitialize(zz_low,  0.0);

   double last_h = 0.0;
   double last_l = 0.0;
   double dev    = deviation * point_size;

   for(int i = depth; i < rates_total; ++i)
   {
      // local high
      double m = high[i]; int mi = i;
      for(int k = i - depth + 1; k <= i; ++k)
         if(high[k] > m) { m = high[k]; mi = k; }
      if(mi == i && (last_h == 0.0 || (m - last_h) > dev))
      {
         zz_high[i] = m;
         last_h = m;
      }
      // local low
      double n = low[i]; int ni = i;
      for(int k = i - depth + 1; k <= i; ++k)
         if(low[k] < n) { n = low[k]; ni = k; }
      if(ni == i && (last_l == 0.0 || (last_l - n) > dev))
      {
         zz_low[i] = n;
         last_l = n;
      }
   }

   EwbPivot raw[];
   ArrayResize(raw, 0);
   int    last_type = 0;
   double last_p    = 0.0;
   int    last_bar  = -10000;

   for(int i = 0; i < rates_total; ++i)
   {
      if(zz_high[i] != 0.0)
      {
         if(last_type == 1)
         {
            if(zz_high[i] >= last_p && ArraySize(raw) > 0)
            {
               int n = ArraySize(raw) - 1;
               raw[n].time  = time[i];
               raw[n].price = zz_high[i];
               raw[n].bar   = i;
               raw[n].type  = EWB_PIVOT_HIGH;
               last_p   = zz_high[i];
               last_bar = i;
            }
         }
         else if(i - last_bar >= backstep || last_type == 0)
         {
            EwbPivot p;
            p.time  = time[i]; p.price = zz_high[i];
            p.bar   = i;       p.type  = EWB_PIVOT_HIGH;
            int n = ArraySize(raw); ArrayResize(raw, n + 1);
            raw[n] = p;
            last_type = 1; last_p = zz_high[i]; last_bar = i;
         }
      }
      if(zz_low[i] != 0.0)
      {
         if(last_type == -1)
         {
            if(zz_low[i] <= last_p && ArraySize(raw) > 0)
            {
               int n = ArraySize(raw) - 1;
               raw[n].time  = time[i];
               raw[n].price = zz_low[i];
               raw[n].bar   = i;
               raw[n].type  = EWB_PIVOT_LOW;
               last_p   = zz_low[i];
               last_bar = i;
            }
         }
         else if(i - last_bar >= backstep || last_type == 0)
         {
            EwbPivot p;
            p.time  = time[i]; p.price = zz_low[i];
            p.bar   = i;       p.type  = EWB_PIVOT_LOW;
            int n = ArraySize(raw); ArrayResize(raw, n + 1);
            raw[n] = p;
            last_type = -1; last_p = zz_low[i]; last_bar = i;
         }
      }
   }

   int total = ArraySize(raw);
   int keep  = (total < max_pivots) ? total : max_pivots;
   ArrayResize(out, keep);
   for(int j = 0; j < keep; ++j)
      out[j] = raw[total - keep + j];
   return keep;
}

//==================================================================+
//                       WAVE COUNT CORE                             |
//==================================================================+
void EwbInitWaveCount(EwbWaveCount &wc)
{
   wc.direction = EWB_DIR_NONE;
   wc.status    = EWB_ST_NONE;
   wc.bias      = EWB_DIR_NONE;
   wc.waves_found = 0;
   wc.rule_w2_no_full_retrace = false;
   wc.rule_w3_not_shortest    = false;
   wc.rule_w4_no_overlap      = false;
   wc.rule_w3_beyond_w1       = false;
   wc.rule_w4_no_full_retrace = false;
   wc.score_clarity    = 0.0;
   wc.score_fib        = 0.0;
   wc.score_rules      = 0.0;
   wc.score_projection = 0.0;
   wc.confidence = 0;
   wc.position_text = "No clean count";
   wc.alt_text      = "";
   wc.warnings      = "";
}

bool EwbAlternation(const EwbPivotType a, const EwbPivotType b)
{
   return (a == EWB_PIVOT_HIGH && b == EWB_PIVOT_LOW) ||
          (a == EWB_PIVOT_LOW  && b == EWB_PIVOT_HIGH);
}

// Validate the cardinal rules and project a 0..1 score.
void EwbValidateCardinalRules(EwbWaveCount &wc)
{
   if(wc.direction == EWB_DIR_NONE)
   {
      wc.score_rules = 0.0;
      return;
   }

   double w1s = wc.p0.price;
   double w1e = wc.p1.price;
   bool   have_w2 = wc.waves_found >= 2;
   bool   have_w3 = wc.waves_found >= 3;
   bool   have_w4 = wc.waves_found >= 4;
   bool   have_w5 = wc.waves_found >= 5;

   double w2e = have_w2 ? wc.p2.price : 0.0;
   double w3e = have_w3 ? wc.p3.price : 0.0;
   double w4e = have_w4 ? wc.p4.price : 0.0;
   double w5e = have_w5 ? wc.p5.price : 0.0;

   double len_w1 = MathAbs(w1e - w1s);
   double len_w3 = (have_w3) ? MathAbs(w3e - w2e) : 0.0;
   double len_w5 = (have_w5) ? MathAbs(w5e - w4e) : 0.0;

   // R1: Wave 2 never retraces > 100% of Wave 1.
   if(have_w2)
   {
      if(wc.direction == EWB_DIR_BULLISH) wc.rule_w2_no_full_retrace = (w2e > w1s);
      else                                wc.rule_w2_no_full_retrace = (w2e < w1s);
   }
   else wc.rule_w2_no_full_retrace = true;

   // Bonus: Wave 3 always travels beyond Wave 1.
   if(have_w3)
   {
      if(wc.direction == EWB_DIR_BULLISH) wc.rule_w3_beyond_w1 = (w3e > w1e);
      else                                wc.rule_w3_beyond_w1 = (w3e < w1e);
   }
   else wc.rule_w3_beyond_w1 = true;

   // R3: Wave 4 does not enter Wave 1 territory.
   if(have_w4)
   {
      if(wc.direction == EWB_DIR_BULLISH) wc.rule_w4_no_overlap = (w4e > w1e);
      else                                wc.rule_w4_no_overlap = (w4e < w1e);
   }
   else wc.rule_w4_no_overlap = true;

   // Bonus: Wave 4 never fully retraces Wave 3.
   if(have_w4)
   {
      if(wc.direction == EWB_DIR_BULLISH) wc.rule_w4_no_full_retrace = (w4e > w2e);
      else                                wc.rule_w4_no_full_retrace = (w4e < w2e);
   }
   else wc.rule_w4_no_full_retrace = true;

   // R2: Wave 3 never the shortest of W1/W3/W5.
   if(have_w5)
      wc.rule_w3_not_shortest = (len_w3 >= len_w1 - 1e-12) && (len_w3 >= len_w5 - 1e-12);
   else if(have_w3)
      wc.rule_w3_not_shortest = (len_w3 >= len_w1 - 1e-12);
   else
      wc.rule_w3_not_shortest = true;

   double pts = 0.0; double max_pts = 0.0;
   if(have_w2) { max_pts += 1.0; if(wc.rule_w2_no_full_retrace) pts += 1.0; }
   if(have_w3) { max_pts += 1.0; if(wc.rule_w3_beyond_w1)       pts += 1.0; }
   if(have_w4) { max_pts += 1.0; if(wc.rule_w4_no_overlap)      pts += 1.0; }
   if(have_w4) { max_pts += 0.5; if(wc.rule_w4_no_full_retrace) pts += 0.5; }
   if(have_w3) { max_pts += 1.0; if(wc.rule_w3_not_shortest)    pts += 1.0; }
   wc.score_rules = (max_pts > 0.0) ? (pts / max_pts) : 0.0;
}

void EwbScoreFibonacci(EwbWaveCount &wc)
{
   double w1s = wc.p0.price;
   double w1e = wc.p1.price;
   double len_w1 = MathAbs(w1e - w1s);
   if(len_w1 <= 0.0) { wc.score_fib = 0.0; return; }

   bool have_w2 = wc.waves_found >= 2;
   bool have_w3 = wc.waves_found >= 3;
   bool have_w4 = wc.waves_found >= 4;
   bool have_w5 = wc.waves_found >= 5;

   double s_w2 = 0.0, s_w3 = 0.0, s_w4 = 0.0, s_w5 = 0.0;
   double n = 0.0;

   if(have_w2)
   {
      double r = MathAbs(wc.p2.price - w1e) / len_w1;
      // typical W2 retraces .500 / .618 / .786 (sharp)
      s_w2 = EwbBestProximity3(r, EWB_FIBO_500, EWB_FIBO_618, EWB_FIBO_786, 0.18);
      n += 1.0;
   }
   if(have_w3)
   {
      double len3 = MathAbs(wc.p3.price - wc.p2.price);
      double r3 = len3 / len_w1;
      // typical W3 = 1.618x or 2.618x of W1
      s_w3 = EwbBestProximity3(r3, EWB_FIBO_1618, EWB_FIBO_2618, EWB_FIBO_1000, 0.40);
      n += 1.0;
   }
   if(have_w4)
   {
      double len3 = MathAbs(wc.p3.price - wc.p2.price);
      if(len3 > 0.0)
      {
         double r4 = MathAbs(wc.p3.price - wc.p4.price) / len3;
         // typical W4 = .236 / .382 / .500 of W3 (sideways)
         s_w4 = EwbBestProximity3(r4, EWB_FIBO_382, EWB_FIBO_236, EWB_FIBO_500, 0.18);
         n += 1.0;
      }
   }
   if(have_w5)
   {
      double len5 = MathAbs(wc.p5.price - wc.p4.price);
      double r5 = len5 / len_w1;
      // typical W5 = 1.000 / 0.618 / 1.618 of W1
      s_w5 = EwbBestProximity3(r5, EWB_FIBO_1000, EWB_FIBO_618, EWB_FIBO_1618, 0.40);
      n += 1.0;
   }

   double total = s_w2 + s_w3 + s_w4 + s_w5;
   wc.score_fib = (n > 0.0) ? (total / n) : 0.0;

   if(have_w5)
   {
      double len5 = MathAbs(wc.p5.price - wc.p4.price);
      double r5 = len5 / len_w1;
      wc.score_projection = EwbBestProximity3(r5, EWB_FIBO_1000, EWB_FIBO_618, EWB_FIBO_1618, 0.50);
   }
   else if(have_w3)
   {
      double len3 = MathAbs(wc.p3.price - wc.p2.price);
      double r3 = len3 / len_w1;
      wc.score_projection = EwbBestProximity3(r3, EWB_FIBO_1618, EWB_FIBO_2618, EWB_FIBO_1000, 0.50);
   }
}

void EwbAggregateConfidence(EwbWaveCount &wc)
{
   wc.score_clarity = (wc.waves_found >= 5 ? 1.0 :
                       wc.waves_found >= 4 ? 0.8 :
                       wc.waves_found >= 3 ? 0.6 :
                       wc.waves_found >= 2 ? 0.4 :
                       wc.waves_found >= 1 ? 0.2 : 0.0);

   double composite =
      0.30 * wc.score_clarity +
      0.30 * wc.score_rules +
      0.25 * wc.score_fib +
      0.15 * wc.score_projection;

   int conf = (int)MathRound(composite * 100.0);
   if(conf < 0)   conf = 0;
   if(conf > 100) conf = 100;

   bool hard_break = (wc.waves_found >= 2 && !wc.rule_w2_no_full_retrace) ||
                     (wc.waves_found >= 3 && !wc.rule_w3_not_shortest)    ||
                     (wc.waves_found >= 4 && !wc.rule_w4_no_overlap);
   if(hard_break && conf > 30) conf = 30;

   wc.confidence = conf;
}

string EwbWavePositionText(const EwbWaveCount &wc)
{
   string dir_str = (wc.direction == EWB_DIR_BULLISH) ? "BULLISH" :
                    (wc.direction == EWB_DIR_BEARISH) ? "BEARISH" : "NEUTRAL";

   switch(wc.status)
   {
      case EWB_ST_W1_DONE:    return "Wave 1 complete - " + dir_str;
      case EWB_ST_W2_DONE:    return "Wave 2 complete - watching W3 - " + dir_str;
      case EWB_ST_W3_FORMING: return "Wave 3 in progress - " + dir_str;
      case EWB_ST_W3_DONE:    return "Wave 3 complete - " + dir_str;
      case EWB_ST_W4_DONE:    return "Wave 4 complete - watching W5 - " + dir_str;
      case EWB_ST_W5_FORMING: return "Wave 5 in progress - " + dir_str;
      case EWB_ST_W5_DONE:    return "Wave 5 complete - correction expected";
      case EWB_ST_A_DONE:     return "Wave A complete - watching B";
      case EWB_ST_B_DONE:     return "Wave B complete - watching C";
      case EWB_ST_C_DONE:     return "Wave C complete - new impulse possible";
   }
   return "No clean count";
}

string EwbAlternativeText(const EwbWaveCount &wc)
{
   if(wc.status == EWB_ST_W3_DONE || wc.status == EWB_ST_W4_DONE)
      return "Alt: count could already be in C of a flat";
   if(wc.status == EWB_ST_W5_DONE)
      return "Alt: extended impulse, expect deeper retrace";
   if(wc.status == EWB_ST_C_DONE)
      return "Alt: triangle / running flat - wait for confirmation";
   return "";
}

string EwbWarningsText(const EwbWaveCount &wc)
{
   string s = "";
   if(wc.waves_found >= 2 && !wc.rule_w2_no_full_retrace) s += "R1 broken (W2 fully retraced W1). ";
   if(wc.waves_found >= 3 && !wc.rule_w3_not_shortest)    s += "R2 broken (W3 shortest). ";
   if(wc.waves_found >= 4 && !wc.rule_w4_no_overlap)      s += "R3 broken (W4 overlaps W1). ";
   if(wc.waves_found >= 3 && !wc.rule_w3_beyond_w1)       s += "W3 did not exceed W1 end. ";
   return s;
}

// Try a candidate impulse starting at index i0 in the pivots array.
// Returns true if a structurally valid count is found and fills wc.
// Confidence is computed but the caller must compare candidates.
bool EwbTryImpulseAt(const EwbPivot &pivots[], const int i0,
                     EwbWaveCount &wc)
{
   EwbInitWaveCount(wc);
   int n = ArraySize(pivots);
   int avail = n - i0;
   if(avail < 2) return false; // need at least p0 and p1

   EwbPivot p[6];
   p[0] = pivots[i0];
   if(i0 + 1 < n) p[1] = pivots[i0 + 1];
   for(int k = 2; k < 6; ++k)
   {
      if(i0 + k < n) p[k] = pivots[i0 + k];
      else
      {
         p[k].type = EWB_PIVOT_NONE;
      }
   }

   if(p[0].type == EWB_PIVOT_NONE || p[1].type == EWB_PIVOT_NONE) return false;
   if(!EwbAlternation(p[0].type, p[1].type)) return false;

   // direction
   wc.direction = (p[0].type == EWB_PIVOT_LOW) ? EWB_DIR_BULLISH : EWB_DIR_BEARISH;
   wc.p0 = p[0]; wc.p1 = p[1];
   wc.waves_found = 1;
   wc.status = EWB_ST_W1_DONE;

   // continue while alternation holds and structural progress is correct
   for(int k = 2; k < 6; ++k)
   {
      if(p[k].type == EWB_PIVOT_NONE) break;
      if(!EwbAlternation(p[k-1].type, p[k].type)) break;

      // check directional progress
      bool ok = true;
      if(wc.direction == EWB_DIR_BULLISH)
      {
         if(k == 1) ok = (p[1].price > p[0].price);
         if(k == 3) ok = (p[3].price > p[1].price);
         if(k == 5) ok = (p[5].price > p[3].price);
         if(k == 2) ok = (p[2].price < p[1].price && p[2].price > p[0].price);
         if(k == 4) ok = (p[4].price < p[3].price && p[4].price > p[1].price);
      }
      else
      {
         if(k == 1) ok = (p[1].price < p[0].price);
         if(k == 3) ok = (p[3].price < p[1].price);
         if(k == 5) ok = (p[5].price < p[3].price);
         if(k == 2) ok = (p[2].price > p[1].price && p[2].price < p[0].price);
         if(k == 4) ok = (p[4].price > p[3].price && p[4].price < p[1].price);
      }
      if(!ok) break;

      if(k == 2) { wc.p2 = p[2]; wc.waves_found = 2; wc.status = EWB_ST_W2_DONE; }
      if(k == 3) { wc.p3 = p[3]; wc.waves_found = 3; wc.status = EWB_ST_W3_DONE; }
      if(k == 4) { wc.p4 = p[4]; wc.waves_found = 4; wc.status = EWB_ST_W4_DONE; }
      if(k == 5) { wc.p5 = p[5]; wc.waves_found = 5; wc.status = EWB_ST_W5_DONE; }
   }

   if(wc.waves_found < 2) return false;

   // build forming flags: if the next pivot is missing but price has moved
   // beyond the previous pivot, mark it as "forming"
   if(wc.waves_found == 2 && i0 + 3 >= n)
   {
      double last = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      bool moving = (wc.direction == EWB_DIR_BULLISH) ? (last > wc.p1.price)
                                                       : (last < wc.p1.price);
      if(moving) wc.status = EWB_ST_W3_FORMING;
   }
   if(wc.waves_found == 4 && i0 + 5 >= n)
   {
      double last = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      bool moving = (wc.direction == EWB_DIR_BULLISH) ? (last > wc.p3.price)
                                                       : (last < wc.p3.price);
      if(moving) wc.status = EWB_ST_W5_FORMING;
   }

   // ABC after a complete impulse
   if(wc.waves_found == 5)
   {
      if(i0 + 6 < n) { wc.pA = pivots[i0 + 6]; wc.status = EWB_ST_A_DONE; }
      if(i0 + 7 < n) { wc.pB = pivots[i0 + 7]; wc.status = EWB_ST_B_DONE; }
      if(i0 + 8 < n) { wc.pC = pivots[i0 + 8]; wc.status = EWB_ST_C_DONE; }
   }

   wc.bias = wc.direction;
   if(wc.status == EWB_ST_W5_DONE)
      wc.bias = (wc.direction == EWB_DIR_BULLISH) ? EWB_DIR_BEARISH : EWB_DIR_BULLISH;

   EwbValidateCardinalRules(wc);
   EwbScoreFibonacci(wc);
   EwbAggregateConfidence(wc);

   wc.position_text = EwbWavePositionText(wc);
   wc.alt_text      = EwbAlternativeText(wc);
   wc.warnings      = EwbWarningsText(wc);
   return true;
}

// Search for the best Elliott count among recent pivots.
bool EwbAnalyseWaves(const EwbPivot &pivots[], EwbWaveCount &wc)
{
   EwbInitWaveCount(wc);
   int n = ArraySize(pivots);
   if(n < 3)
   {
      wc.position_text = "Need more pivots";
      return false;
   }

   EwbWaveCount best;
   EwbInitWaveCount(best);
   bool have_best = false;

   // Sweep candidate origins; favor more recent counts (higher i0).
   int i0_min = 0;
   int i0_max = n - 2;
   for(int i0 = i0_min; i0 <= i0_max; ++i0)
   {
      EwbWaveCount cand;
      if(!EwbTryImpulseAt(pivots, i0, cand)) continue;

      if(InpRequireAllRules)
      {
         if(cand.waves_found >= 2 && !cand.rule_w2_no_full_retrace) continue;
         if(cand.waves_found >= 3 && !cand.rule_w3_not_shortest)    continue;
         if(cand.waves_found >= 4 && !cand.rule_w4_no_overlap)      continue;
      }

      // recency bonus: prefer counts that include the latest pivot
      int last_idx = i0 + cand.waves_found;
      if(cand.status >= EWB_ST_A_DONE) last_idx = i0 + 5 +
         (cand.status == EWB_ST_A_DONE ? 1 :
          cand.status == EWB_ST_B_DONE ? 2 : 3);
      double recency = (double)(last_idx) / (double)(n - 1);
      int adj_conf = cand.confidence + (int)MathRound(recency * 10.0);
      if(adj_conf > 100) adj_conf = 100;

      if(!have_best || adj_conf > best.confidence)
      {
         best = cand;
         best.confidence = adj_conf;
         have_best = true;
      }
   }

   if(have_best)
   {
      wc = best;
      return true;
   }

   wc.position_text = "No clean Elliott count";
   return false;
}

//==================================================================+
//                       TRADE SETUP                                 |
//==================================================================+
void EwbInitTradeSetup(EwbTradeSetup &ts)
{
   ts.kind  = EWB_SETUP_NONE;
   ts.side  = EWB_SIDE_NONE;
   ts.entry = 0.0; ts.sl = 0.0;
   ts.tp1   = 0.0; ts.tp2 = 0.0; ts.tp3 = 0.0;
   ts.rr    = 0.0;
   ts.valid = false;
   ts.label = "";
}

bool EwbBuildW4toW5(const EwbWaveCount &wc, const double sl_buf_pts,
                    const double point_size, EwbTradeSetup &ts)
{
   EwbInitTradeSetup(ts);
   if(wc.waves_found < 4) return false;
   if(wc.status != EWB_ST_W4_DONE && wc.status != EWB_ST_W5_FORMING) return false;

   double w1s = wc.p0.price;
   double w1e = wc.p1.price;
   double w4e = wc.p4.price;
   double len_w1 = MathAbs(w1e - w1s);
   double buf    = sl_buf_pts * point_size;
   if(len_w1 <= 0.0) return false;

   ts.kind  = EWB_SETUP_W4_TO_W5;
   ts.label = "W4 -> W5 continuation";

   if(wc.direction == EWB_DIR_BULLISH)
   {
      ts.side  = EWB_SIDE_BUY;
      ts.entry = w4e;
      ts.sl    = w1e - buf;     // R3-aware invalidation
      ts.tp1   = w4e + len_w1 * EWB_FIBO_618;
      ts.tp2   = w4e + len_w1 * EWB_FIBO_1000;
      ts.tp3   = w4e + len_w1 * EWB_FIBO_1618;
   }
   else if(wc.direction == EWB_DIR_BEARISH)
   {
      ts.side  = EWB_SIDE_SELL;
      ts.entry = w4e;
      ts.sl    = w1e + buf;
      ts.tp1   = w4e - len_w1 * EWB_FIBO_618;
      ts.tp2   = w4e - len_w1 * EWB_FIBO_1000;
      ts.tp3   = w4e - len_w1 * EWB_FIBO_1618;
   }
   else return false;

   double risk   = MathAbs(ts.entry - ts.sl);
   double reward = MathAbs(ts.tp2   - ts.entry);
   ts.rr    = (risk > 0.0) ? reward / risk : 0.0;
   ts.valid = (risk > 0.0) && (ts.rr > 0.0);
   return ts.valid;
}

bool EwbBuildEndOfC(const EwbWaveCount &wc, const double sl_buf_pts,
                    const double point_size, EwbTradeSetup &ts)
{
   EwbInitTradeSetup(ts);
   if(wc.status != EWB_ST_C_DONE) return false;

   double w0   = wc.p0.price;
   double w5   = wc.p5.price;
   double pc   = wc.pC.price;
   double len5 = MathAbs(w5 - w0);
   if(len5 <= 0.0) return false;

   ts.kind  = EWB_SETUP_END_OF_C;
   ts.label = "End of C -> new impulse";
   double buf = sl_buf_pts * point_size;

   // After ABC the new impulse goes in the original direction (bias).
   if(wc.bias == EWB_DIR_BULLISH ||
      (wc.bias == EWB_DIR_NONE && wc.direction == EWB_DIR_BULLISH))
   {
      ts.side  = EWB_SIDE_BUY;
      ts.entry = pc;
      ts.sl    = pc - buf;
      ts.tp1   = pc + len5 * EWB_FIBO_382;
      ts.tp2   = pc + len5 * EWB_FIBO_618;
      ts.tp3   = pc + len5 * EWB_FIBO_1000;
   }
   else
   {
      ts.side  = EWB_SIDE_SELL;
      ts.entry = pc;
      ts.sl    = pc + buf;
      ts.tp1   = pc - len5 * EWB_FIBO_382;
      ts.tp2   = pc - len5 * EWB_FIBO_618;
      ts.tp3   = pc - len5 * EWB_FIBO_1000;
   }

   double risk   = MathAbs(ts.entry - ts.sl);
   double reward = MathAbs(ts.tp2   - ts.entry);
   ts.rr    = (risk > 0.0) ? reward / risk : 0.0;
   ts.valid = (risk > 0.0) && (ts.rr > 0.0);
   return ts.valid;
}

void EwbBuildBestSetup(const EwbWaveCount &wc, EwbTradeSetup &ts)
{
   EwbInitTradeSetup(ts);
   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   EwbTradeSetup ts_w; EwbTradeSetup ts_c;
   bool has_w = InpAllowW4ToW5 && EwbBuildW4toW5(wc, InpSLBufferPoints, pt, ts_w);
   bool has_c = InpAllowEndOfC && EwbBuildEndOfC(wc, InpSLBufferPoints, pt, ts_c);
   if(has_w && has_c)
   {
      if(ts_w.rr >= ts_c.rr) ts = ts_w;
      else                    ts = ts_c;
   }
   else if(has_w) ts = ts_w;
   else if(has_c) ts = ts_c;
}

//==================================================================+
//                       RISK MANAGER                                |
//==================================================================+
double EwbComputeLotSize(const double balance, const double risk_pct,
                         const double sl_dist, const double tick_value,
                         const double tick_size, const double vol_min,
                         const double vol_max, const double vol_step)
{
   if(balance <= 0.0 || risk_pct <= 0.0) return 0.0;
   if(sl_dist <= 0.0 || tick_value <= 0.0 || tick_size <= 0.0) return 0.0;
   double risk_money = balance * (risk_pct / 100.0);
   double per_pt     = tick_value / tick_size;
   double lots       = risk_money / (sl_dist * per_pt);
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
//                       OBJECT HELPERS                              |
//==================================================================+
void EwbDestroyAll(const string prefix)
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; --i)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, prefix) == 0) ObjectDelete(0, nm);
   }
}

void EwbLabel(const string name, const int x, const int y,
              const string text, const color clr, const int fsz = EWB_PANEL_FONT,
              const string fnt = EWB_PANEL_FONTNAME, const bool bold = false)
{
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
   ObjectSetString (0, name, OBJPROP_FONT, bold ? (fnt + " Bold") : fnt);
}

void EwbRect(const string name, const int x, const int y, const int w, const int h,
             const color bg, const color border)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
}

void EwbButton(const string name, const int x, const int y, const int w, const int h,
               const string text, const color bg, const color text_clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, EWB_C_PANEL_BORDER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, EWB_PANEL_FONT);
      ObjectSetString (0, name, OBJPROP_FONT, EWB_PANEL_FONTNAME);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_clr);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
}

void EwbChartText(const string name, const datetime t, const double price,
                  const string text, const color clr, const ENUM_ANCHOR_POINT anchor,
                  const int fsz)
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
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fsz);
   ObjectSetString (0, name, OBJPROP_FONT, EWB_PANEL_FONTNAME);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
}

void EwbTrendLine(const string name, const datetime t1, const double p1,
                  const datetime t2, const double p2, const color clr,
                  const int width, const ENUM_LINE_STYLE style)
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

void EwbHLine(const string name, const double price, const color clr,
              const int width, const ENUM_LINE_STYLE style)
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

datetime EwbRightEdgeTime()
{
   datetime now = iTime(_Symbol, _Period, 0);
   int      ps  = PeriodSeconds(_Period);
   return now + 8 * ps;
}

//==================================================================+
//                       PANEL RENDER                                |
//==================================================================+
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

string EwbStatusMessage()
{
   switch(g_state)
   {
      case EWB_RUN_ANALYZING: return "Analyzing...";
      case EWB_RUN_RENDERING: return "Updating chart...";
      case EWB_RUN_NEED_BARS: return "Need more bars";
      default:                return "Ready - click Sync";
   }
}

void EwbRenderPanel(const string symbol, const ENUM_TIMEFRAMES tf,
                    const datetime updated, const EwbWaveCount &wc,
                    const EwbTradeSetup &ts)
{
   const int x  = InpPanelX;
   const int y  = InpPanelY;
   const int w  = EWB_PANEL_W;
   const int lh = EWB_PANEL_LH;
   const string p = EWB_PFX;

   // background + header
   const int total_h = 540;
   EwbRect(p + "bg",     x, y, w, total_h, EWB_C_PANEL_BG, EWB_C_PANEL_BORDER);
   EwbRect(p + "hdr_bg", x, y, w, 28,      EWB_C_PANEL_HEADER, EWB_C_PANEL_HEADER);
   EwbLabel(p + "title", x + 10, y + 6, "Elliott Wave Analyzer", EWB_C_TITLE, EWB_PANEL_FONT + 1, EWB_PANEL_FONTNAME, true);
   EwbButton(p + "sync_btn", x + w - 64, y + 4, 56, 20, "SYNC", EWB_C_TITLE, clrBlack);

   int row = y + 36;

   // info rows
   EwbLabel(p + "lab_sym", x + 10, row, "Symbol",     EWB_C_LABEL);
   EwbLabel(p + "val_sym", x + 110, row, symbol,      EWB_C_VALUE);
   row += lh;
   EwbLabel(p + "lab_tf",  x + 10, row, "Timeframe",  EWB_C_LABEL);
   EwbLabel(p + "val_tf",  x + 110, row, EwbTfText(tf), EWB_C_VALUE);
   row += lh;
   EwbLabel(p + "lab_upd", x + 10, row, "Updated",    EWB_C_LABEL);
   EwbLabel(p + "val_upd", x + 110, row, TimeToString(updated, TIME_DATE | TIME_MINUTES), EWB_C_VALUE);
   row += lh;
   color st_clr = (g_state == EWB_RUN_NEED_BARS) ? EWB_C_BAD : EWB_C_VALUE;
   EwbLabel(p + "lab_st",  x + 10, row, "Status",     EWB_C_LABEL);
   EwbLabel(p + "val_st",  x + 110, row, EwbStatusMessage(), st_clr);
   row += lh + 8;

   // ---- WAVE COUNT ----
   EwbRect (p + "div_wc", x + 8, row + 2, w - 16, 1, EWB_C_PANEL_BORDER, EWB_C_PANEL_BORDER);
   row += 6;
   EwbLabel(p + "wc_hdr", x + 10, row, "WAVE COUNT", EWB_C_HEADING, EWB_PANEL_FONT, EWB_PANEL_FONTNAME, true);
   row += lh;
   color pos_clr = (wc.direction == EWB_DIR_BULLISH) ? EWB_C_BUY :
                   (wc.direction == EWB_DIR_BEARISH) ? EWB_C_SELL : EWB_C_LABEL;
   EwbLabel(p + "wc_pos", x + 10, row, wc.position_text, pos_clr);
   row += lh;

   // confidence: bar + value
   EwbLabel(p + "lab_cf", x + 10, row, "Confidence", EWB_C_LABEL);
   const int bar_x = x + 110;
   const int bar_w = 150;
   const int bar_h = 12;
   EwbRect(p + "cf_bg",   bar_x, row + 2, bar_w, bar_h, (color)C'60,60,60', EWB_C_PANEL_BORDER);
   int filled = (int)MathRound(wc.confidence * (bar_w - 2) / 100.0);
   if(filled < 0) filled = 0;
   if(filled > bar_w - 2) filled = bar_w - 2;
   color cf_clr = (wc.confidence >= 70 ? EWB_C_GOOD :
                   wc.confidence >= 40 ? EWB_C_WARN : EWB_C_BAD);
   if(filled > 0)
      EwbRect(p + "cf_fg", bar_x + 1, row + 3, filled, bar_h - 2, cf_clr, cf_clr);
   else
      ObjectDelete(0, p + "cf_fg");
   EwbLabel(p + "val_cf", bar_x + bar_w + 8, row, StringFormat("%d/100", wc.confidence), cf_clr);
   row += lh + 2;

   EwbLabel(p + "lab_bias", x + 10, row, "Bias", EWB_C_LABEL);
   string bias_txt = (wc.bias == EWB_DIR_BULLISH) ? "BULLISH" :
                     (wc.bias == EWB_DIR_BEARISH) ? "BEARISH" : "NEUTRAL";
   color  bias_clr = (wc.bias == EWB_DIR_BULLISH) ? EWB_C_BUY :
                     (wc.bias == EWB_DIR_BEARISH) ? EWB_C_SELL : EWB_C_LABEL;
   EwbLabel(p + "val_bias", x + 110, row, bias_txt, bias_clr);
   row += lh + 6;

   // ---- TRADE SETUP ----
   EwbRect (p + "div_ts", x + 8, row + 2, w - 16, 1, EWB_C_PANEL_BORDER, EWB_C_PANEL_BORDER);
   row += 6;
   EwbLabel(p + "ts_hdr", x + 10, row, "TRADE SETUP", EWB_C_HEADING, EWB_PANEL_FONT, EWB_PANEL_FONTNAME, true);
   row += lh;

   if(ts.valid)
   {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      string side_txt = (ts.side == EWB_SIDE_BUY) ? "BUY" : "SELL";
      color  side_clr = (ts.side == EWB_SIDE_BUY) ? EWB_C_BUY : EWB_C_SELL;
      EwbLabel(p + "lab_bs", x + 10, row, "Bias",         EWB_C_LABEL);
      EwbLabel(p + "val_bs", x + 110, row, side_txt,      side_clr, EWB_PANEL_FONT, EWB_PANEL_FONTNAME, true);
      row += lh;
      EwbLabel(p + "lab_e",  x + 10, row, "Entry",        EWB_C_LABEL);
      EwbLabel(p + "val_e",  x + 110, row, DoubleToString(ts.entry, digits), EWB_C_ENTRY);
      row += lh;
      EwbLabel(p + "lab_sl", x + 10, row, "Stop Loss",    EWB_C_LABEL);
      EwbLabel(p + "val_sl", x + 110, row, DoubleToString(ts.sl,    digits), EWB_C_SL);
      row += lh;
      EwbLabel(p + "lab_t1", x + 10, row, "TP1",          EWB_C_LABEL);
      EwbLabel(p + "val_t1", x + 110, row, DoubleToString(ts.tp1,   digits), EWB_C_TP1);
      row += lh;
      EwbLabel(p + "lab_t2", x + 10, row, "TP2",          EWB_C_LABEL);
      EwbLabel(p + "val_t2", x + 110, row, DoubleToString(ts.tp2,   digits), EWB_C_TP2);
      row += lh;
      EwbLabel(p + "lab_t3", x + 10, row, "TP3",          EWB_C_LABEL);
      EwbLabel(p + "val_t3", x + 110, row, DoubleToString(ts.tp3,   digits), EWB_C_TP3);
      row += lh;
      color rr_clr = (ts.rr >= 2.0 ? EWB_C_GOOD : ts.rr >= 1.0 ? EWB_C_WARN : EWB_C_BAD);
      EwbLabel(p + "lab_rr", x + 10, row, "R/R",          EWB_C_LABEL);
      EwbLabel(p + "val_rr", x + 110, row, DoubleToString(ts.rr, 2), rr_clr);
      row += lh + 4;
      EwbLabel(p + "inv_note", x + 10, row,
               StringFormat("Invalidation if price breaks: %s",
                            DoubleToString(ts.sl, digits)), EWB_C_WARN);
      row += lh;
   }
   else
   {
      EwbLabel(p + "lab_bs", x + 10, row, "No setup yet - waiting for clean count", EWB_C_LABEL);
      string clears[] = {"val_bs","lab_e","val_e","lab_sl","val_sl",
                         "lab_t1","val_t1","lab_t2","val_t2","lab_t3","val_t3",
                         "lab_rr","val_rr","inv_note"};
      for(int i = 0; i < ArraySize(clears); ++i)
         ObjectDelete(0, p + clears[i]);
      row += lh;
   }

   // alt count note
   EwbLabel(p + "alt_note", x + 10, row, wc.alt_text, EWB_C_LABEL);
   row += lh + 4;

   // ---- RULES ----
   EwbRect (p + "div_rl", x + 8, row + 2, w - 16, 1, EWB_C_PANEL_BORDER, EWB_C_PANEL_BORDER);
   row += 6;
   EwbLabel(p + "rl_hdr", x + 10, row, "ELLIOTT RULES", EWB_C_HEADING, EWB_PANEL_FONT, EWB_PANEL_FONTNAME, true);
   row += lh;
   EwbLabel(p + "lab_r1", x + 10, row, "R1  W2 <= W1",       EWB_C_LABEL);
   EwbLabel(p + "val_r1", x + 200, row, wc.rule_w2_no_full_retrace ? "OK" : "FAIL",
            wc.rule_w2_no_full_retrace ? EWB_C_GOOD : EWB_C_BAD);
   row += lh;
   EwbLabel(p + "lab_r2", x + 10, row, "R2  W3 not shortest", EWB_C_LABEL);
   EwbLabel(p + "val_r2", x + 200, row, wc.rule_w3_not_shortest ? "OK" : "FAIL",
            wc.rule_w3_not_shortest ? EWB_C_GOOD : EWB_C_BAD);
   row += lh;
   EwbLabel(p + "lab_r3", x + 10, row, "R3  W4 != W1 zone",   EWB_C_LABEL);
   EwbLabel(p + "val_r3", x + 200, row, wc.rule_w4_no_overlap ? "OK" : "FAIL",
            wc.rule_w4_no_overlap ? EWB_C_GOOD : EWB_C_BAD);
   row += lh + 4;

   // ---- WARNINGS ----
   if(StringLen(wc.warnings) > 0)
   {
      EwbLabel(p + "warn", x + 10, row, wc.warnings, EWB_C_WARN);
   }
   else
   {
      ObjectDelete(0, p + "warn");
   }
}

//==================================================================+
//                       CHART OVERLAY                               |
//==================================================================+
ENUM_ANCHOR_POINT EwbLabelAnchor(const EwbPivotType t)
{
   // High pivot -> label sits above (anchor lower)
   // Low pivot  -> label sits below (anchor upper)
   return (t == EWB_PIVOT_HIGH) ? ANCHOR_LOWER : ANCHOR_UPPER;
}

void EwbRenderWaveOverlay(const EwbWaveCount &wc)
{
   const string p = EWB_PFX + "wv_";
   const int    fsz = InpLabelFontSize;
   const ENUM_LINE_STYLE st = InpWaveLineStyle;
   const int    lw = InpWaveLineWidth;

   // clear all wave objects first - simpler than tracking deltas
   EwbDestroyAll(p);

   if(wc.waves_found < 1) return;

   // origin "0"
   if(InpDrawWaveLabels)
      EwbChartText(p + "lbl0", wc.p0.time, wc.p0.price, "0",
                   EWB_C_LABEL, EwbLabelAnchor(wc.p0.type), fsz);

   // 0->1
   if(InpDrawTrendLines)
      EwbTrendLine(p + "01", wc.p0.time, wc.p0.price, wc.p1.time, wc.p1.price, EWB_C_W1, lw, st);
   if(InpDrawWaveLabels)
      EwbChartText(p + "lbl1", wc.p1.time, wc.p1.price, "1",
                   EWB_C_W1, EwbLabelAnchor(wc.p1.type), fsz);

   if(wc.waves_found >= 2)
   {
      if(InpDrawTrendLines)
         EwbTrendLine(p + "12", wc.p1.time, wc.p1.price, wc.p2.time, wc.p2.price, EWB_C_W2, lw, st);
      if(InpDrawWaveLabels)
         EwbChartText(p + "lbl2", wc.p2.time, wc.p2.price, "2",
                      EWB_C_W2, EwbLabelAnchor(wc.p2.type), fsz);
   }
   if(wc.waves_found >= 3)
   {
      if(InpDrawTrendLines)
         EwbTrendLine(p + "23", wc.p2.time, wc.p2.price, wc.p3.time, wc.p3.price, EWB_C_W3, lw, st);
      if(InpDrawWaveLabels)
         EwbChartText(p + "lbl3", wc.p3.time, wc.p3.price, "3",
                      EWB_C_W3, EwbLabelAnchor(wc.p3.type), fsz);
   }
   if(wc.waves_found >= 4)
   {
      if(InpDrawTrendLines)
         EwbTrendLine(p + "34", wc.p3.time, wc.p3.price, wc.p4.time, wc.p4.price, EWB_C_W4, lw, st);
      if(InpDrawWaveLabels)
         EwbChartText(p + "lbl4", wc.p4.time, wc.p4.price, "4",
                      EWB_C_W4, EwbLabelAnchor(wc.p4.type), fsz);
   }
   if(wc.waves_found >= 5)
   {
      if(InpDrawTrendLines)
         EwbTrendLine(p + "45", wc.p4.time, wc.p4.price, wc.p5.time, wc.p5.price, EWB_C_W5, lw, st);
      if(InpDrawWaveLabels)
         EwbChartText(p + "lbl5", wc.p5.time, wc.p5.price, "5",
                      EWB_C_W5, EwbLabelAnchor(wc.p5.type), fsz);
   }
   if(wc.status >= EWB_ST_A_DONE)
   {
      if(InpDrawTrendLines)
         EwbTrendLine(p + "5A", wc.p5.time, wc.p5.price, wc.pA.time, wc.pA.price, EWB_C_ABC, lw, st);
      if(InpDrawWaveLabels)
         EwbChartText(p + "lblA", wc.pA.time, wc.pA.price, "A",
                      EWB_C_ABC, EwbLabelAnchor(wc.pA.type), fsz);
   }
   if(wc.status >= EWB_ST_B_DONE)
   {
      if(InpDrawTrendLines)
         EwbTrendLine(p + "AB", wc.pA.time, wc.pA.price, wc.pB.time, wc.pB.price, EWB_C_ABC, lw, st);
      if(InpDrawWaveLabels)
         EwbChartText(p + "lblB", wc.pB.time, wc.pB.price, "B",
                      EWB_C_ABC, EwbLabelAnchor(wc.pB.type), fsz);
   }
   if(wc.status >= EWB_ST_C_DONE)
   {
      if(InpDrawTrendLines)
         EwbTrendLine(p + "BC", wc.pB.time, wc.pB.price, wc.pC.time, wc.pC.price, EWB_C_ABC, lw, st);
      if(InpDrawWaveLabels)
         EwbChartText(p + "lblC", wc.pC.time, wc.pC.price, "C",
                      EWB_C_ABC, EwbLabelAnchor(wc.pC.type), fsz);
   }
}

void EwbRenderTradeLines(const EwbTradeSetup &ts)
{
   const string p = EWB_PFX + "tl_";
   string keys[] = {"entry","sl","tp1","tp2","tp3","entry_t","sl_t","tp1_t","tp2_t","tp3_t"};
   if(!ts.valid)
   {
      for(int i = 0; i < ArraySize(keys); ++i) ObjectDelete(0, p + keys[i]);
      return;
   }

   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const datetime te = EwbRightEdgeTime();
   const ENUM_LINE_STYLE st = InpLevelStyle;
   const int lw = InpLevelWidth;

   if(InpDrawEntry)
   {
      EwbHLine    (p + "entry",   ts.entry, EWB_C_ENTRY, lw, st);
      EwbChartText(p + "entry_t", te, ts.entry,
                   StringFormat("Entry %s", DoubleToString(ts.entry, digits)),
                   EWB_C_ENTRY, ANCHOR_LEFT_LOWER, EWB_PANEL_FONT);
   }
   else { ObjectDelete(0, p + "entry"); ObjectDelete(0, p + "entry_t"); }

   if(InpDrawSL)
   {
      EwbHLine    (p + "sl",   ts.sl, EWB_C_SL, lw, st);
      EwbChartText(p + "sl_t", te, ts.sl,
                   StringFormat("SL %s", DoubleToString(ts.sl, digits)),
                   EWB_C_SL, ANCHOR_LEFT_LOWER, EWB_PANEL_FONT);
   }
   else { ObjectDelete(0, p + "sl"); ObjectDelete(0, p + "sl_t"); }

   if(InpDrawTP1)
   {
      EwbHLine    (p + "tp1",   ts.tp1, EWB_C_TP1, lw, st);
      EwbChartText(p + "tp1_t", te, ts.tp1,
                   StringFormat("TP1 %s", DoubleToString(ts.tp1, digits)),
                   EWB_C_TP1, ANCHOR_LEFT_LOWER, EWB_PANEL_FONT);
   }
   else { ObjectDelete(0, p + "tp1"); ObjectDelete(0, p + "tp1_t"); }

   if(InpDrawTP2)
   {
      EwbHLine    (p + "tp2",   ts.tp2, EWB_C_TP2, lw, st);
      EwbChartText(p + "tp2_t", te, ts.tp2,
                   StringFormat("TP2 %s", DoubleToString(ts.tp2, digits)),
                   EWB_C_TP2, ANCHOR_LEFT_LOWER, EWB_PANEL_FONT);
   }
   else { ObjectDelete(0, p + "tp2"); ObjectDelete(0, p + "tp2_t"); }

   if(InpDrawTP3)
   {
      EwbHLine    (p + "tp3",   ts.tp3, EWB_C_TP3, lw, st);
      EwbChartText(p + "tp3_t", te, ts.tp3,
                   StringFormat("TP3 %s", DoubleToString(ts.tp3, digits)),
                   EWB_C_TP3, ANCHOR_LEFT_LOWER, EWB_PANEL_FONT);
   }
   else { ObjectDelete(0, p + "tp3"); ObjectDelete(0, p + "tp3_t"); }
}

void EwbRenderFibLevels(const EwbWaveCount &wc)
{
   const string p = EWB_PFX + "fb_";
   if(!InpDrawFibLevels || wc.waves_found < 2)
   {
      EwbDestroyAll(p);
      return;
   }
   double w1s = wc.p0.price;
   double w1e = wc.p1.price;
   double range = w1e - w1s;
   if(MathAbs(range) <= 0.0) return;

   double levels[] = {EWB_FIBO_236, EWB_FIBO_382, EWB_FIBO_500,
                      EWB_FIBO_618, EWB_FIBO_786,
                      EWB_FIBO_1000, EWB_FIBO_1272, EWB_FIBO_1618,
                      EWB_FIBO_2000, EWB_FIBO_2618};
   string  names[]  = {"23.6","38.2","50.0","61.8","78.6",
                       "100","127.2","161.8","200","261.8"};
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const datetime te = EwbRightEdgeTime();

   for(int i = 0; i < ArraySize(levels); ++i)
   {
      double price = (levels[i] <= 1.0)
                       ? (w1e - range * levels[i])     // retracement
                       : (w1s + range * levels[i]);    // extension
      string nm = p + IntegerToString(i);
      EwbHLine    (nm,         price, EWB_C_FIB, InpFibWidth, InpFibStyle);
      EwbChartText(nm + "_t", te, price,
                   StringFormat("Fib %s%% %s", names[i], DoubleToString(price, digits)),
                   EWB_C_FIB, ANCHOR_LEFT_LOWER, EWB_PANEL_FONT);
   }
}

//==================================================================+
//                       PIPELINE                                    |
//==================================================================+
bool EwbRecomputeAnalysis()
{
   int avail = Bars(_Symbol, _Period);
   int look  = (InpBarsToAnalyze < avail) ? InpBarsToAnalyze : avail;
   if(look < InpZZDepth * 4)
   {
      g_state = EWB_RUN_NEED_BARS;
      EwbInitWaveCount(g_wc);
      EwbInitTradeSetup(g_setup);
      return false;
   }

   g_state = EWB_RUN_ANALYZING;

   double  high[];  double  low[];  datetime time[];
   ArraySetAsSeries(high, false);
   ArraySetAsSeries(low,  false);
   ArraySetAsSeries(time, false);
   if(CopyHigh(_Symbol, _Period, 0, look, high) <= 0) return false;
   if(CopyLow (_Symbol, _Period, 0, look, low)  <= 0) return false;
   if(CopyTime(_Symbol, _Period, 0, look, time) <= 0) return false;

   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int n_pivots = EwbDetectPivots(high, low, time, look,
                                  InpZZDepth, InpZZDeviation, InpZZBackstep,
                                  pt, InpMaxPivots, g_pivots);

   bool ok = false;
   if(n_pivots >= 3)
      ok = EwbAnalyseWaves(g_pivots, g_wc);
   else
      EwbInitWaveCount(g_wc);

   EwbInitTradeSetup(g_setup);
   if(ok) EwbBuildBestSetup(g_wc, g_setup);

   g_last_analysis = TimeCurrent();
   g_state = EWB_RUN_IDLE;
   return ok;
}

bool EwbHasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
      if(g_pos.SelectByIndex(i))
         if(g_pos.Magic() == InpMagic && g_pos.Symbol() == _Symbol)
            return true;
   return false;
}

void EwbTryPlaceTrade()
{
   if(!InpAutoTrade)         return;
   if(!g_setup.valid)        return;
   if(g_wc.confidence < InpMinConfidence) return;
   if(g_setup.rr < InpMinRR) return;
   if(EwbHasOpenPosition())  return;
   if(InpRequireAllRules)
   {
      if(!g_wc.rule_w2_no_full_retrace) return;
      if(!g_wc.rule_w3_not_shortest)    return;
      if(!g_wc.rule_w4_no_overlap)      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price_now = (g_setup.side == EWB_SIDE_BUY) ? ask : bid;

   double sl_dist = MathAbs(price_now - g_setup.sl);
   if(sl_dist <= 0.0) return;

   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstp = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double lots = EwbComputeLotSize(bal, InpRiskPercent, sl_dist, tv, ts, vmin, vmax, vstp);
   if(lots < vmin) return;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   string cmt = StringFormat("EWB %s [%d/100]", g_setup.label, g_wc.confidence);
   bool sent = false;
   if(g_setup.side == EWB_SIDE_BUY)
      sent = g_trade.Buy(lots, _Symbol, ask, g_setup.sl, g_setup.tp2, cmt);
   else if(g_setup.side == EWB_SIDE_SELL)
      sent = g_trade.Sell(lots, _Symbol, bid, g_setup.sl, g_setup.tp2, cmt);
   if(!sent)
      Print("EWB trade rejected: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
}

void EwbRenderAll()
{
   g_state = EWB_RUN_RENDERING;
   EwbRenderPanel(_Symbol, _Period, g_last_analysis, g_wc, g_setup);
   EwbRenderWaveOverlay(g_wc);
   EwbRenderTradeLines(g_setup);
   EwbRenderFibLevels(g_wc);
   ChartRedraw();
   g_state = EWB_RUN_IDLE;
}

//==================================================================+
//                       EVENT HANDLERS                              |
//==================================================================+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);

   EwbDestroyAll(EWB_PFX);
   EwbInitWaveCount(g_wc);
   EwbInitTradeSetup(g_setup);

   EwbRecomputeAnalysis();
   EwbRenderAll();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EwbDestroyAll(EWB_PFX);
   ChartRedraw();
}

void OnTick()
{
   datetime cur = iTime(_Symbol, _Period, 0);
   bool new_bar = (cur != g_last_bar_time);

   if(new_bar)
   {
      g_last_bar_time = cur;
      if(InpAutoSyncOnNewBar)
      {
         EwbRecomputeAnalysis();
         EwbRenderAll();
         EwbTryPlaceTrade();
      }
   }
   else
   {
      // refresh "Updated" timestamp on every tick (cheap)
      EwbLabel(EWB_PFX + "val_upd",
               InpPanelX + 110,
               InpPanelY + 36 + EWB_PANEL_LH * 2,
               TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
               EWB_C_VALUE);
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      string sync_name = EWB_PFX + "sync_btn";
      if(sparam == sync_name)
      {
         EwbRecomputeAnalysis();
         EwbRenderAll();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
   }
}

//+------------------------------------------------------------------+
