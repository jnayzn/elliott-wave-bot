//+------------------------------------------------------------------+
//|                                                WaveCounter.mqh  |
//|                                  Elliott Wave Bot — Wave logic  |
//+------------------------------------------------------------------+
//|  Identifies the most recent 5-wave impulse and (when present)    |
//|  ABC corrective sequence from a list of ZigZag pivots, validates |
//|  the three Cardinal Rules of impulse construction, and returns a |
//|  confidence score blended from rule compliance and Fibonacci     |
//|  guideline matches.                                              |
//|                                                                  |
//|  THE THREE CARDINAL RULES (Frost & Prechter, "Elliott Wave       |
//|  Principle", Lesson 4):                                          |
//|    R1) Wave 2 never retraces more than 100% of Wave 1.           |
//|    R2) Wave 3 is never the shortest of the three actionary       |
//|        waves (1, 3, 5) of a motive wave.                         |
//|    R3) Wave 4 does not enter the territory of Wave 1 (impulse).  |
//|        (Diagonal triangles are the only 5-wave structures where  |
//|         Wave 4 may overlap Wave 1.)                              |
//|                                                                  |
//|  Additional rules enforced:                                      |
//|    - Wave 3 always travels beyond the end of Wave 1.             |
//|    - Wave 4 never retraces more than 100% of Wave 3.             |
//+------------------------------------------------------------------+
#property copyright "Elliott Wave Bot"
#property strict
#ifndef __EWB_WAVE_COUNTER_MQH__
#define __EWB_WAVE_COUNTER_MQH__

#include "ZigZagDetector.mqh"
#include "FiboRatios.mqh"

enum EwbWaveDirection
{
   EWB_WAVE_DIR_NONE     = 0,
   EWB_WAVE_DIR_BULLISH  = 1,
   EWB_WAVE_DIR_BEARISH  = -1
};

enum EwbWaveStatus
{
   EWB_WAVE_STATUS_NONE          = 0,  // no clean count
   EWB_WAVE_STATUS_DEVELOPING    = 1,  // 1-2-3 forming, not yet 5
   EWB_WAVE_STATUS_IMPULSE_DONE  = 2,  // five complete waves identified
   EWB_WAVE_STATUS_ABC_FORMING   = 3,  // post-5 correction in progress
   EWB_WAVE_STATUS_ABC_COMPLETE  = 4   // ABC complete — new impulse possible
};

// Result of analysing a pivot sequence.
struct EwbWaveCount
{
   EwbWaveDirection direction;
   EwbWaveStatus    status;

   // Pivots of the impulse phase.
   EwbPivot         p0;   // origin (start of W1)
   EwbPivot         p1;   // end of W1
   EwbPivot         p2;   // end of W2
   EwbPivot         p3;   // end of W3
   EwbPivot         p4;   // end of W4
   EwbPivot         p5;   // end of W5

   // ABC correction (only when status >= ABC_FORMING).
   EwbPivot         pA;
   EwbPivot         pB;
   EwbPivot         pC;

   // Cardinal rule compliance. All true means the count is valid.
   bool             rule_w2_no_full_retrace; // R1
   bool             rule_w3_not_shortest;    // R2
   bool             rule_w4_no_overlap;      // R3
   bool             rule_w3_beyond_w1;       // bonus
   bool             rule_w4_no_full_retrace; // bonus

   // Fibonacci guideline compliance scores (0..1).
   double           score_w2_retrace;
   double           score_w3_extension;
   double           score_w4_retrace;
   double           score_w5_projection;
   double           score_alternation;

   // Aggregate 0..100 confidence.
   int              confidence;

   // Bias for the next move.
   EwbWaveDirection bias;

   // Free-form analyst note.
   string           note;
};

//+------------------------------------------------------------------+
//|  Helper: returns true if the pivot sequence p0..p5 follows a     |
//|  bullish impulse pattern (low/high/low/high/low/high).           |
//+------------------------------------------------------------------+
bool EwbIsBullishSequence(const EwbPivot &p0, const EwbPivot &p1, const EwbPivot &p2,
                          const EwbPivot &p3, const EwbPivot &p4, const EwbPivot &p5)
{
   return p0.type == EWB_PIVOT_LOW  && p1.type == EWB_PIVOT_HIGH &&
          p2.type == EWB_PIVOT_LOW  && p3.type == EWB_PIVOT_HIGH &&
          p4.type == EWB_PIVOT_LOW  && p5.type == EWB_PIVOT_HIGH;
}

bool EwbIsBearishSequence(const EwbPivot &p0, const EwbPivot &p1, const EwbPivot &p2,
                          const EwbPivot &p3, const EwbPivot &p4, const EwbPivot &p5)
{
   return p0.type == EWB_PIVOT_HIGH && p1.type == EWB_PIVOT_LOW  &&
          p2.type == EWB_PIVOT_HIGH && p3.type == EWB_PIVOT_LOW  &&
          p4.type == EWB_PIVOT_HIGH && p5.type == EWB_PIVOT_LOW;
}

//+------------------------------------------------------------------+
//|  Initialise an empty WaveCount.                                  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//|  Validate the cardinal rules on an impulse and fill the rule_*  |
//|  flags. Direction must be set on `wc` before the call.          |
//+------------------------------------------------------------------+
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

   // R1: Wave 2 never retraces more than 100% of Wave 1.
   if(wc.direction == EWB_WAVE_DIR_BULLISH)
      wc.rule_w2_no_full_retrace = (w2_end > w1_start);
   else
      wc.rule_w2_no_full_retrace = (w2_end < w1_start);

   // R3: Wave 4 does not enter Wave 1 territory (only meaningful once W4 exists).
   if(wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
   {
      if(wc.direction == EWB_WAVE_DIR_BULLISH)
         wc.rule_w4_no_overlap = (w4_end > w1_end);
      else
         wc.rule_w4_no_overlap = (w4_end < w1_end);
   }
   else
   {
      wc.rule_w4_no_overlap = true; // not applicable yet
   }

   // Bonus rule: Wave 4 never retraces more than 100% of Wave 3.
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

   // Bonus rule: Wave 3 always travels beyond the end of Wave 1.
   if(wc.direction == EWB_WAVE_DIR_BULLISH)
      wc.rule_w3_beyond_w1 = (w3_end > w1_end);
   else
      wc.rule_w3_beyond_w1 = (w3_end < w1_end);

   // R2: Wave 3 is never the shortest of W1, W3, W5 (only checkable if W5 exists).
   if(wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
   {
      wc.rule_w3_not_shortest = (len_w3 >= len_w1) && (len_w3 >= len_w5);
   }
   else
   {
      // Pre-W5: only require W3 >= W1 to flag the "not shortest" risk early.
      wc.rule_w3_not_shortest = (len_w3 >= len_w1);
   }
}

//+------------------------------------------------------------------+
//|  Score Fibonacci guideline matches and aggregate confidence.    |
//+------------------------------------------------------------------+
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

   // W2 retracement of W1 — sharp corrections favour .500 and .618.
   double w2_ratio = EwbRetracementRatio(w1_start, w1_end, w2_end);
   double w2_targets[3];
   w2_targets[0] = EWB_FIBO_500;
   w2_targets[1] = EWB_FIBO_618;
   w2_targets[2] = EWB_FIBO_786;
   wc.score_w2_retrace = EwbBestProximityScore(w2_ratio, w2_targets, 0.10);

   // W3 extension of W1 — most impulses extend W3 to 1.618 or 2.618.
   double w3_ratio = len_w3 / len_w1;
   double w3_targets[3];
   w3_targets[0] = EWB_FIBO_1618;
   w3_targets[1] = EWB_FIBO_2618;
   w3_targets[2] = EWB_FIBO_1000;
   wc.score_w3_extension = EwbBestProximityScore(w3_ratio, w3_targets, 0.30);

   // W4 retracement of W3 — sideways corrections favour .382.
   if(len_w3 > 0.0 && wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
   {
      double w4_ratio = MathAbs(w3_end - w4_end) / len_w3;
      double w4_targets[3];
      w4_targets[0] = EWB_FIBO_382;
      w4_targets[1] = EWB_FIBO_236;
      w4_targets[2] = EWB_FIBO_500;
      wc.score_w4_retrace = EwbBestProximityScore(w4_ratio, w4_targets, 0.10);
   }

   // W5 projection — W5 ≈ W1 (equality) or .618×W1 or 1.618×W1.
   if(len_w5 > 0.0 && len_w1 > 0.0 && wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
   {
      double w5_ratio = len_w5 / len_w1;
      double w5_targets[3];
      w5_targets[0] = EWB_FIBO_1000;
      w5_targets[1] = EWB_FIBO_618;
      w5_targets[2] = EWB_FIBO_1618;
      wc.score_w5_projection = EwbBestProximityScore(w5_ratio, w5_targets, 0.30);
   }

   // Alternation guideline.
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

   // Aggregate confidence: cardinal rules dominate (60 pts) + guidelines (40 pts).
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
   if(total < 0) total = 0;
   if(total > 100) total = 100;
   wc.confidence = total;

   // If any cardinal rule is broken, cap confidence at 30.
   if(!wc.rule_w2_no_full_retrace || !wc.rule_w3_not_shortest || !wc.rule_w4_no_overlap)
   {
      if(wc.confidence > 30) wc.confidence = 30;
   }
}

//+------------------------------------------------------------------+
//|  Tag a note describing the count's situation.                   |
//+------------------------------------------------------------------+
void EwbTagNote(EwbWaveCount &wc)
{
   switch(wc.status)
   {
      case EWB_WAVE_STATUS_DEVELOPING:
         wc.note = "Impulse forming - watch for clean W3";
         break;
      case EWB_WAVE_STATUS_IMPULSE_DONE:
         wc.note = "Trend maturity - watch for reversal";
         break;
      case EWB_WAVE_STATUS_ABC_FORMING:
         wc.note = "ABC correction in progress";
         break;
      case EWB_WAVE_STATUS_ABC_COMPLETE:
         wc.note = "ABC complete - new impulse possible";
         break;
      default:
         wc.note = "No clean Elliott count detected";
         break;
   }
}

//+------------------------------------------------------------------+
//|  Try to fit a 5-wave impulse + optional ABC to a pivot list.    |
//|  Pivots are oldest-first. Returns true if at least 3 waves are  |
//|  identified (W1, W2, W3).                                       |
//+------------------------------------------------------------------+
bool EwbAnalyseWaves(const EwbPivot &pivots[], EwbWaveCount &wc)
{
   EwbInitWaveCount(wc);
   int n = ArraySize(pivots);
   if(n < 4) return false;

   // 1) ABC complete: pivots[n-9..n-1] = 0,1,2,3,4,5,A,B,C
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

      bool bull = EwbIsBullishSequence(p0, p1, p2, p3, p4, p5);
      bool bear = EwbIsBearishSequence(p0, p1, p2, p3, p4, p5);
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

   // 2) Impulse done.
   if(n >= 6)
   {
      EwbPivot p0 = pivots[n-6];
      EwbPivot p1 = pivots[n-5];
      EwbPivot p2 = pivots[n-4];
      EwbPivot p3 = pivots[n-3];
      EwbPivot p4 = pivots[n-2];
      EwbPivot p5 = pivots[n-1];

      bool bull = EwbIsBullishSequence(p0, p1, p2, p3, p4, p5);
      bool bear = EwbIsBearishSequence(p0, p1, p2, p3, p4, p5);
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

   // 3) Developing (4 pivots: 0,1,2,3).
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

#endif // __EWB_WAVE_COUNTER_MQH__
