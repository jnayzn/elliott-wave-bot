# Trading strategy

This document explains *exactly* how the bot turns Elliott Wave analysis into trade orders. Read this before enabling `InpAutoTrade`.

## Pipeline overview

On every **new bar**, the EA runs:

```
1. Pull last InpHistoryBars of OHLC data
2. Run ZigZag pivot detection            → pivot list (oldest-first)
3. Try to fit Elliott patterns to pivots → WaveCount + Status
4. Validate Cardinal Rules (R1, R2, R3) → rule flags
5. Score Fibonacci guidelines            → 0..100 confidence + bias
6. If status >= IMPULSE_DONE:
       Build "W4 → W5" continuation setup
   If status == ABC_COMPLETE:
       Build "End of C → new impulse" setup
   Pick whichever has higher R/R
7. Render HUD panel + wave labels + Entry/SL/TP lines
8. If InpAutoTrade && filters pass:
       Compute lot size for InpRiskPercent% balance risk
       Send market order
```

## Pivot detection

We use a **self-contained ZigZag** (re-implemented in `ZigZagDetector.mqh`) rather than `iCustom("ZigZag", ...)` for two reasons:
1. **No external dependency** — the EA compiles standalone.
2. **Deterministic across brokers** — no risk of broker-specific ZigZag variations.

Three knobs:
- `InpZZDepth` (default 12): minimum bars between two extrema.
- `InpZZDeviation` (default 5 points): minimum reversal in points to register a new pivot.
- `InpZZBackstep` (default 3 bars): minimum bar separation between alternating pivots.

The output is a **list of alternating high/low pivots**, oldest-first, capped at `InpMaxPivots` (default 12). The wave-counter only looks at the most recent 4-9 pivots.

## Wave identification

The wave-counter tries three patterns, in priority order:

### 1) ABC complete (9 pivots)

`pivots[n-9 .. n-1]` are interpreted as `0,1,2,3,4,5,A,B,C`. For a **bullish** structure:
- p0 must be a LOW
- p1 a HIGH (top of W1)
- p2 a LOW (bottom of W2)
- p3 a HIGH (top of W3, beyond p1)
- p4 a LOW (bottom of W4, above p1 — no overlap)
- p5 a HIGH (top of W5)
- pA a LOW
- pB a HIGH
- pC a LOW (target for new impulse)

(Mirror image for bearish structures.)

If the pattern matches AND all four cardinal rules pass, status = `ABC_COMPLETE`.

### 2) Impulse done (6 pivots)

`pivots[n-6 .. n-1]` = `0,1,2,3,4,5`. Same alternation/rule constraints. Status = `IMPULSE_DONE`. Bias flips against the impulse direction (expect ABC retracement next).

### 3) Developing (4 pivots)

`pivots[n-4 .. n-1]` = `0,1,2,3`. Cardinal rules R1 + W3-beyond-W1 are checked. Status = `DEVELOPING`. No trade is set up yet (W4 doesn't exist).

## Confidence score (0-100)

The score is composed of:

| Component | Max points | Source |
|---|---|---|
| R1 (W2 ≤ W1) | 15 | cardinal rule |
| R2 (W3 not shortest) | 15 | cardinal rule |
| R3 (no W1-W4 overlap) | 15 | cardinal rule |
| W3 beyond W1 | 8 | bonus rule |
| W4 ≤ W3 | 7 | bonus rule |
| W2 retracement near 0.500/0.618/0.786 | 8 | guideline |
| W3 extension near 1.618/2.618/1.000 | 12 | guideline |
| W4 retracement near 0.382/0.236/0.500 | 8 | guideline |
| W5 projection near 1.000/0.618/1.618 of W1 | 8 | guideline |
| Alternation (W2 sharp ↔ W4 sideways) | 4 | guideline |

**If any cardinal rule is broken**, the confidence is capped at 30. With `InpRequireAllRules = true` (default) the bot will refuse to trade these counts entirely, so the cap only matters for analyst-mode display.

## Trade setups

### A) Wave 4 → Wave 5 continuation

Conditions: status ≥ `IMPULSE_DONE`. (Activates at the moment W4 has just printed, before W5 develops fully — the bot enters on a break of W3 in the impulse direction.)

For a **bullish** impulse:
- **Entry** = price of W3 high (a sell-stop above for entry-on-break, or a market order if price already pulled back into W4's territory).
- **SL** = price of W1 high − `InpSLBufferPoints * point_size`. Logic: a return below W1's terminal point breaks Cardinal Rule 3 (W4 must not enter W1 territory). That is the count-invalidation level.
- **TP1** = W4 + W1 length × 1.000 → "W5 = W1" equality target.
- **TP2** = W4 + W1 length × 1.618.
- **TP3** = W4 + W1 length × 2.618.

Mirror for bearish.

**Why this works**: Wave 5 typically equals Wave 1 (most common) or extends to 1.618× or 2.618× when Wave 5 itself is the extended wave.

### B) End of C → new impulse

Conditions: status == `ABC_COMPLETE`. The just-completed ABC is interpreted as a counter-trend retracement of the prior 5-wave; we expect a new impulse to launch from C in the same direction as the prior 5-wave.

For a prior **bullish** 5-wave + ABC down:
- **Bias** = bullish (resume the prior trend after the ABC pullback).
- **Entry** = price at C pivot.
- **SL** = C − `InpSLBufferPoints * point_size`.
- **TP1** = C + 5-wave length × 0.382.
- **TP2** = C + 5-wave length × 0.618.
- **TP3** = C + 5-wave length × 1.000 (full retrace of the original move).

**Why this works**: After a clean 3-wave ABC pullback, the new impulse usually re-tests the prior W5 high and often makes a new high.

### Setup selection

When both setups are valid simultaneously (rare), the bot picks the one with the **higher R/R** (computed as |TP1 − Entry| / |Entry − SL|).

## Filters before sending an order

A trade is only sent when **all** of these pass:

- `InpAutoTrade = true`
- `g_setup.valid = true`
- `g_wc.confidence >= InpMinConfidence` (default 60)
- `g_setup.rr >= InpMinRR` (default 1.5)
- `!HasOpenPosition()` — only one EWB position per symbol at a time.
- `InpRequireAllRules` ⇒ all three cardinal rules pass.
- The current price is **close enough to the entry** (within |TP1 − Entry|). This rejects stale signals where price has already run far past the ideal entry.

## Position sizing

Risk-based sizing in `RiskManager.mqh`:

```
risk_money              = balance × (InpRiskPercent / 100)
money_per_lot_per_point = tick_value / tick_size
lots                    = risk_money / (sl_distance × money_per_lot_per_point)
lots                    = clamp(lots, volume_min, volume_max)
lots                    = floor(lots / volume_step) × volume_step
```

This guarantees that a SL hit costs **exactly** `InpRiskPercent`% of balance, modulo broker rounding. With `InpRiskPercent = 1.0` and 100 trades, a 50% win-rate at R/R = 1.5 yields a positive expectancy of `(0.5 × 1.5 − 0.5 × 1.0) = 0.25R per trade ≈ +25R = +25%` over 100 trades — assuming reality matches the model, which it never quite does.

## What the bot is NOT

- Not a HFT bot. It runs on **bar close** of the configured timeframe.
- Not a martingale or grid system. One position max per symbol.
- Not a pyramid scheme — it does not add to winners.
- Not multi-timeframe — it analyses the chart's timeframe in isolation.
- Not a holy grail. Elliott Wave is **subjective**; even with strict cardinal rule enforcement, alternative counts always exist.

## Safety recommendations

1. **Always test on a demo account** for at least 4 weeks before going live.
2. **Backtest** at least 6-12 months across the timeframes you'll use.
3. Start with `InpRiskPercent = 0.5%` until you have a track record.
4. Keep `InpRequireAllRules = true` — disabling it allows the bot to trade rule-breaking counts.
5. Set up MT5 *Push notifications* so you're alerted when an order is placed.
