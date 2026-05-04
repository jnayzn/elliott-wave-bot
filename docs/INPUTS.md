# EA Inputs reference

Every input the EA exposes, with default, units, and tuning advice.

## Group: ZigZag (pivot detection)

### `InpZZDepth` *(int, default 12)*

Minimum number of bars required between two consecutive ZigZag extrema. Larger values produce **fewer, more significant** pivots (longer-degree wave counts). Lower values produce **more noise** but catch sub-degree waves earlier.

- Recommended: 8-15 on H4, 12-20 on H1, 15-30 on M15.
- Too low (≤ 5): ZigZag flips back and forth on every minor swing — counts become unstable.
- Too high (≥ 30 on H4): the bot only sees mega-degree pivots, missing tradeable setups.

### `InpZZDeviation` *(int, default 5)*

Minimum reversal in **points** required to register a new pivot. A point is the symbol's smallest price increment (`SymbolInfoDouble(_Symbol, SYMBOL_POINT)`).

- For a 5-digit FX symbol like EURUSD: 5 points = 0.5 pip.
- Increase to filter low-volatility chop. Decrease to catch tighter swings.

### `InpZZBackstep` *(int, default 3)*

Minimum bar distance between alternating pivots (high → low → high → ...). Together with depth, this prevents same-bar or near-bar pivot stuttering.

### `InpHistoryBars` *(int, default 1500)*

Number of bars from the chart's right edge that the EA scans for pivots on each recompute. Larger = the EA can see deeper history (catch larger-degree counts) but uses more CPU. 1500 H4 bars ≈ 250 trading days of look-back.

### `InpMaxPivots` *(int, default 12)*

Maximum number of pivots kept after ZigZag detection. The wave-counter only ever inspects the most recent 4 (developing), 6 (impulse), or 9 (ABC complete) — so this is essentially a memory cap.

---

## Group: Elliott analysis

### `InpMinConfidence` *(int, default 60)*

Minimum 0-100 confidence score required to consider a setup tradeable. Below this, the panel still displays the count but no order is placed.

- 60 (default): balanced. Filters out the noisiest counts.
- 75-80: aggressive filter. Only A-grade setups, but you'll see far fewer trades.
- 40-50: relaxed. Use on quieter symbols or shorter timeframes where perfect counts are rare.

### `InpRequireAllRules` *(bool, default true)*

When true, the EA refuses to enter trades on any count where R1, R2, or R3 is broken — even if the confidence is high.

**Strongly recommended to leave at `true`**. Turning it off allows the bot to trade rule-violating counts which, by Frost & Prechter's own definition, are not Elliott Wave at all.

### `InpAllowW4ToW5` *(bool, default true)*

Enable the "Wave 4 → Wave 5 continuation" setup.

### `InpAllowEndOfC` *(bool, default true)*

Enable the "End of C → new impulse" reversal setup.

When both are enabled, the bot picks the setup with higher R/R when both are simultaneously valid.

---

## Group: Risk management

### `InpRiskPercent` *(double, default 1.0)*

Percentage of account balance risked on each trade. The lot size is computed so that a SL hit costs **exactly** `InpRiskPercent`% (modulo broker rounding).

- 0.25-0.5%: very conservative. Recommended for the first 50 trades or smaller accounts.
- 1.0% (default): standard professional sizing.
- 2.0%+: aggressive. Avoid unless you have a > 100-trade verified track record.

### `InpMinRR` *(double, default 1.5)*

Minimum reward-to-risk ratio (R/R = |TP1 − Entry| / |Entry − SL|) required to take a trade.

- 1.0: break-even at 50% win-rate.
- 1.5 (default): break-even at 40% win-rate.
- 2.0: break-even at 33% win-rate.
- 3.0+: very selective. You'll see fewer trades but each one needs to win less often.

### `InpSLBufferPoints` *(double, default 50)*

Extra distance in **points** beyond the count-invalidation pivot for the stop-loss. This buffer absorbs spread, slippage, and ZigZag pivot fuzz.

- For most FX brokers (5-digit) on H4: 30-80 is reasonable.
- For 3-digit JPY-pairs: 30-50.
- For indices like US30 or NAS100: 100-300.
- For BTCUSD: 1000-3000 (its "point" is much larger).

If your broker rejects orders with `Invalid stops (10016)`, increase this buffer.

### `InpAutoTrade` *(bool, default false)*

Master switch. When `false`, the bot is in **observer mode** — it computes counts, displays the panel, but never sends orders. When `true`, valid setups (passing all filters) trigger market orders.

**Always start with `false`** for any new symbol/timeframe combination.

---

## Group: Display

### `InpShowHUD` *(bool, default true)*

Show/hide the on-chart HUD panel + wave labels + Entry/SL/TP lines.

### `InpHUDX`, `InpHUDY` *(int, defaults 12, 32)*

Top-left corner of the HUD panel in pixels (relative to the chart's top-left). Useful if you want to move the panel out of the way of other indicators.

### `InpMagic` *(int, default 730501)*

Magic number that tags every order placed by this EA. Use a unique value if you run multiple EWB instances on the same account (e.g., one per symbol/TF).

The default 730501 = 7-3-05-01 = "73 Frost & Prechter, May 1, 1978" — a small homage. You can change it without consequence as long as you don't recycle it across different EWB instances.
