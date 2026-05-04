# Elliott Wave Bot for MetaTrader 5

A professional **Expert Advisor** for MetaTrader 5 that trades according to the strict rules of the **Elliott Wave Principle** (R.N. Elliott, codified by A.J. Frost & Robert Prechter). The bot:

- detects swing pivots with a self-contained ZigZag,
- identifies the most recent **5-wave impulse** and (when present) **ABC corrective sequence**,
- validates the **three Cardinal Rules** of impulse construction on every candidate count and refuses trade entries when any rule is broken,
- scores Fibonacci guideline matches into a **0-100 confidence score**,
- builds **Entry / SL / TP1 / TP2 / TP3** levels with R/R for either a *Wave 4 → Wave 5 continuation* or an *End of C → new impulse* reversal,
- sizes positions by % of balance with full broker volume-constraint handling,
- renders an on-chart **HUD panel + numbered wave labels + Entry/SL/TP horizontal lines** matching the look of the reference Elliott Wave Analyzer.

> ⚠️ **Risk warning.** Algorithmic trading carries substantial risk. Use the bot only on a **demo account** until you have tested it thoroughly and you understand every input it exposes. The MIT licence disclaims all warranty.

## Repository layout

```
elliott-wave-bot/
├── MQL5/
│   ├── Experts/
│   │   └── ElliottWaveBot.mq5             ← the EA itself
│   ├── Include/ElliottWave/
│   │   ├── ZigZagDetector.mqh             ← swing pivot detection
│   │   ├── FiboRatios.mqh                 ← Fibonacci constants & helpers
│   │   ├── WaveCounter.mqh                ← Elliott wave identification + cardinal rule validation
│   │   ├── TradeSetup.mqh                 ← Entry / SL / TP / R-R computation
│   │   ├── RiskManager.mqh                ← position sizing
│   │   └── HUDPanel.mqh                   ← on-chart panel + wave labels
│   └── Presets/
│       ├── EURUSD_H4.set
│       └── GBPUSD_H4.set
├── docs/
│   ├── ELLIOTT_RULES.md                   ← full rules + guidelines reference
│   ├── INSTALLATION.md                    ← step-by-step MT5 install guide
│   ├── STRATEGY.md                        ← trading logic explanation
│   └── INPUTS.md                          ← every EA input documented
└── .github/workflows/lint.yml             ← basic MQL5 syntax checks
```

## Quick start

1. **Download** this repository (or `git clone` it).
2. **Open the MT5 data folder** from MetaTrader 5 → *File → Open Data Folder*. You will land in a folder that contains `MQL5\Experts\`, `MQL5\Include\`, etc.
3. **Copy** the contents of this repo's `MQL5/` folder into the data-folder's `MQL5/` folder so that:
   - `MQL5\Experts\ElliottWaveBot.mq5` is in place,
   - `MQL5\Include\ElliottWave\*.mqh` is in place.
4. **Open MetaEditor** (F4 in MT5), open `ElliottWaveBot.mq5`, and press **F7** to compile. You should see *0 errors, 0 warnings*.
5. **Restart MT5** (or right-click *Expert Advisors* in the Navigator and *Refresh*).
6. **Drag** `ElliottWaveBot` onto a chart. Recommended: H4 or H1.
7. In the input dialog, **leave `InpAutoTrade = false`** for the first run — the bot will only display the panel and the suggested setup; no orders will be placed. Enable auto-trading only after you are satisfied with the analysis.

For a complete walkthrough see [docs/INSTALLATION.md](docs/INSTALLATION.md).

## How it trades

The bot recognises two high-quality Elliott setups:

### Wave 4 → Wave 5 continuation (with-trend)

Once a clean 5-wave impulse has formed (W4 has just printed, W5 is forming or imminent), the bot enters in the direction of the impulse on a break of W3:

- **Entry** = high (or low) of W3
- **SL** = just past W1's far edge (cardinal rule R3 invalidation)
- **TP1** = W1 length projected from W4 (W5 = W1 equality)
- **TP2** = 1.618 × W1 from W4
- **TP3** = 2.618 × W1 from W4

### End of C → new impulse (counter-trend reversal)

After a complete 5-wave impulse plus an ABC correction (status = `ABC_COMPLETE`), the bot anticipates a fresh impulse from the C pivot:

- **Entry** = C pivot
- **SL** = just past C
- **TP1** = 0.382 retrace of the prior 5-wave move from C
- **TP2** = 0.618 retrace
- **TP3** = full retrace (1.000)

The bot picks whichever setup yields the **higher R/R**, subject to the `InpMinRR` filter. See [docs/STRATEGY.md](docs/STRATEGY.md) for the full logic.

## The three Cardinal Rules

The bot **never enters a trade** when any of these is violated (when `InpRequireAllRules = true`, the default):

1. **Wave 2 never retraces more than 100% of Wave 1.**
2. **Wave 3 is never the shortest of the three actionary waves (1, 3, 5).**
3. **Wave 4 does not enter the territory of Wave 1** (i.e., no overlap on impulses; diagonal triangles are explicitly excluded as a setup).

See [docs/ELLIOTT_RULES.md](docs/ELLIOTT_RULES.md) for the full rules + guidelines reference.

## Inputs

| Group | Input | Default | Description |
|---|---|---|---|
| ZigZag | `InpZZDepth` | 12 | Minimum bars between extrema |
| ZigZag | `InpZZDeviation` | 5 | Minimum reversal in points |
| ZigZag | `InpZZBackstep` | 3 | Minimum bars between alternating pivots |
| Elliott | `InpMinConfidence` | 60 | Minimum confidence (0-100) to trade |
| Elliott | `InpRequireAllRules` | true | Refuse trade if any cardinal rule broken |
| Risk | `InpRiskPercent` | 1.0 | % of balance risked per trade |
| Risk | `InpMinRR` | 1.5 | Minimum reward-to-risk ratio |
| Risk | `InpAutoTrade` | **false** | Place market orders automatically |

Full reference in [docs/INPUTS.md](docs/INPUTS.md).

## Reference

This bot's logic strictly follows:

- A.J. Frost & Robert R. Prechter Jr., *Elliott Wave Principle: Key to Market Behavior* (10th ed., 2005)
- The free *Comprehensive Course on the Wave Principle* at <https://elliottwave.com>

## License

[MIT](LICENSE). Educational/research use. Trade at your own risk.
