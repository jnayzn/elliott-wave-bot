# Elliott Wave Rules & Guidelines reference

This document collates the rules and guidelines from Frost & Prechter's *Elliott Wave Principle* that the bot enforces or scores. It is **not** a substitute for reading the book; rather, it explains exactly what the EA is doing under the hood and why.

> A **rule** governs all waves to which it applies — breaking a rule invalidates the count.
> A **guideline** is a typical, non-mandatory characteristic — used to score competing counts.

---

## Section 1 — The three Cardinal Rules of impulses

These are the only rules the bot **strictly enforces** before allowing a trade entry.

### R1 — Wave 2 never retraces more than 100% of Wave 1

In a bullish impulse, the low of Wave 2 must remain **above** the start of Wave 1. In a bearish impulse, the high of Wave 2 must remain **below** the start of Wave 1.

```
Bullish:                            Bearish:
        1                                W2
       / \                              /  \
      /   \  W2          W1 ─┐         /    \   W1 ─┐
     /     \  /\               │      /      \ /\    │
    /       \/  \─ must stay   │     /        v      │
W0─/       (W2)   above W0     │ W0─/       (W2)─    │  must stay below W0
                                                     ↓
```

**Why**: Wave 2 is a correction *of* Wave 1. If it fully retraces, Wave 1 wasn't a wave at all — there's no progress.

**EA flag**: `wc.rule_w2_no_full_retrace`

### R2 — Wave 3 is never the shortest of Waves 1, 3, 5

Among the three actionary (with-trend) waves of an impulse, Wave 3 must never be shorter than *both* of Wave 1 and Wave 5.

This rule is **only fully checkable once Wave 5 has printed**. Before then, the EA conservatively requires Wave 3 ≥ Wave 1 to flag the risk early.

**Why**: Wave 3 is the recognition wave — the strongest, fastest move of the sequence, where the crowd commits.

**EA flag**: `wc.rule_w3_not_shortest`

### R3 — Wave 4 does not enter the territory of Wave 1

In an **impulse**, the end of Wave 4 must remain on the same side as Wave 3 relative to the end of Wave 1. Concretely:

- Bullish impulse: low of Wave 4 must be **above** high of Wave 1.
- Bearish impulse: high of Wave 4 must be **below** low of Wave 1.

> **Exception — diagonal triangles.** Diagonal triangles are the only 5-wave structures where Wave 4 may overlap Wave 1. The bot does **not** trade diagonal triangles, so this exception is intentionally irrelevant for our setups.

**EA flag**: `wc.rule_w4_no_overlap`

---

## Section 2 — Bonus rules (also enforced)

In addition to the three cardinal rules, the bot enforces:

### Wave 3 always travels beyond the end of Wave 1

Wave 3 must make new highs/lows beyond Wave 1's terminal extreme.

**EA flag**: `wc.rule_w3_beyond_w1`

### Wave 4 never retraces more than 100% of Wave 3

If Wave 4 retraces all of Wave 3, the count collapses (Wave 3 wasn't really a wave). The bot uses this as a sanity check.

**EA flag**: `wc.rule_w4_no_full_retrace`

---

## Section 3 — Fibonacci guidelines (scored, not enforced)

The bot scores how cleanly the count matches each guideline and aggregates the scores into a 0-100 confidence.

### Wave 2 retracement of Wave 1

Sharp corrections (W2 is usually sharp) tend to retrace **0.500** or **0.618** of Wave 1. Deeper retracements (up to 0.786) are still acceptable.

| Target ratio | Score |
|---|---|
| 0.500 | full credit if exact |
| 0.618 | full credit if exact |
| 0.786 | full credit if exact |

Linearly degrading inside ±0.10 tolerance.

### Wave 3 extension of Wave 1

Wave 3 is most often the **extended** wave. Typical extensions are **1.618×** or **2.618×** Wave 1. Equality (1.000×) is also acceptable.

### Wave 4 retracement of Wave 3

Sideways corrections (W4 is usually sideways — **alternation guideline** applies) tend to retrace **0.382** of Wave 3.

### Wave 5 projection (length)

Common Wave 5 lengths:
- **W1 equality** (Wave 5 = Wave 1)
- **0.618 × Wave 1**
- **1.618 × Wave 1** (rare; usually when Wave 5 extends)

### Alternation guideline

If **Wave 2** is sharp (deep, fast retracement), **Wave 4** will usually be sideways (shallow, slow). And vice-versa. The bot scores 1.0 when this alternation holds, 0.3 otherwise.

### Equality guideline (motive waves)

When Wave 3 is the longest, Waves 1 and 5 tend toward equality or a 0.618 relationship.

---

## Section 4 — Corrective wave guidelines

When the count reaches `ABC_COMPLETE`, the bot looks for these typical ABC relationships (used to refine the End-of-C setup):

### Zigzag

- C ≈ A (equality, most common)
- C = 1.618 × A (extended C)
- C = 0.618 × A (truncated C)

### Regular flat

- A ≈ B ≈ C

### Expanded flat

- C = 1.618 × A (or up to 2.618 × A in rare cases)
- B = 1.236 × A or 1.382 × A (B exceeds A's start, hence "expanded")

### Triangle

- e = 0.618 × c
- c = 0.618 × a
- d = 0.618 × b

The current bot's End-of-C setup uses retracements of the **prior 5-wave move** as targets (rather than absolute ABC ratios) because that anchoring is more robust across pattern types.

---

## Section 5 — What the bot does NOT do (yet)

For full transparency:

- **Diagonal triangles** are not detected as a separate pattern (they are filtered out by the no-overlap rule).
- **Wave extensions** within an impulse (e.g., extended Wave 3 broken down into 5 sub-waves) are not labelled at sub-degree.
- **Truncated 5th** waves are detected via the relaxed scoring on Wave 5 projection but not flagged explicitly.
- **Multiple-degree counts** (e.g., labelling the count we found as "Minute Wave 3" of a "Minor Wave 1") are not produced — the bot operates at a single degree determined by the ZigZag depth.
- **Multi-timeframe confirmation** is not built in — run it on multiple timeframes manually if you want top-down confirmation.

These are deliberate scope limits for v1.0; see `docs/STRATEGY.md` for context.

---

## Section 6 — Reference

> All rules cited here are from A.J. Frost & R.R. Prechter Jr., *Elliott Wave Principle: Key to Market Behavior*, Lessons 4-12 and 20-22.
