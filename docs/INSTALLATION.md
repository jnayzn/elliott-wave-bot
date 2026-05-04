# Installation guide

This guide walks through installing **Elliott Wave Bot** on a MetaTrader 5 terminal from scratch.

## Prerequisites

- **MetaTrader 5** (any broker; demo account is strongly recommended for the first run).
- A MT5 build of **3950 or later** (any build from 2024 onwards is fine). The EA uses `input group` and other modern features.
- A bit of comfort with the **MetaEditor** (F4 inside MT5).

## Step 1 — Open the MT5 data folder

In MT5 click *File → Open Data Folder*. A Windows Explorer window opens at a path that looks like:

```
C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<long-hash>\
```

Inside, you'll see a `MQL5\` folder. Everything you install lives there.

## Step 2 — Copy the bot files

From this repository, copy:

```
MQL5\Experts\ElliottWaveBot.mq5            →   <data folder>\MQL5\Experts\
MQL5\Include\ElliottWave\*.mqh             →   <data folder>\MQL5\Include\ElliottWave\
MQL5\Presets\*.set                         →   <data folder>\MQL5\Presets\        (optional)
```

After copying, your data folder should look like:

```
<data folder>\MQL5\
├── Experts\
│   └── ElliottWaveBot.mq5
├── Include\
│   └── ElliottWave\
│       ├── ZigZagDetector.mqh
│       ├── FiboRatios.mqh
│       ├── WaveCounter.mqh
│       ├── TradeSetup.mqh
│       ├── RiskManager.mqh
│       └── HUDPanel.mqh
└── Presets\
    └── (optional preset .set files)
```

## Step 3 — Compile

1. Open MetaEditor (in MT5 press **F4**, or *Tools → MetaQuotes Language Editor*).
2. In the *Navigator* panel on the left, expand `Experts → ElliottWaveBot.mq5`.
3. Press **F7** (or *Compile*).
4. The output panel at the bottom should show:

   ```
   '*': 0 errors, 0 warnings, ...
   ```

   If you see errors, the most common cause is missing include files. Verify the `Include\ElliottWave\` folder exists at the location described in Step 2.

## Step 4 — Refresh MT5

In MT5, right-click *Expert Advisors* in the *Navigator* (Ctrl+N) and choose *Refresh*. `ElliottWaveBot` should appear under *Expert Advisors*.

## Step 5 — Attach to a chart

1. Open a chart of any symbol. **Recommended**: H4 or H1 timeframe on a major FX pair (EURUSD, GBPUSD, USDJPY) or an index. The EA works on any symbol/timeframe but Elliott Wave reads cleaner on liquid markets and higher timeframes.
2. Drag `ElliottWaveBot` from the *Navigator* onto the chart.
3. The input dialog appears.

## Step 6 — Configure for the first run

For the very first run, leave everything at default **except** verify:

- `InpAutoTrade = false`  ← **important**: the bot will only show the panel & suggested setup, no orders will be placed.
- `InpShowHUD = true`  ← so you can see what the bot is thinking.

Click *OK*.

## Step 7 — Verify the panel renders

You should see the **Elliott Wave Analyzer** panel appear in the top-left of the chart, showing:

- Symbol, Timeframe, last update time, Status
- Direction, Confidence (0-100), Bias
- Trade Setup (Entry / SL / TP1 / TP2 / TP3 / R:R) **if** a valid setup is detected
- Elliott Rules (R1, R2, R3) — each showing YES/NO

If the panel doesn't appear, check:
- The chart's *AutoTrading* button (top toolbar) is **green** (Algo Trading enabled).
- *Tools → Options → Expert Advisors* has *Allow Algorithmic Trading* checked.
- The bot icon in the top-right of the chart shows a green smiley face.

## Step 8 — Enabling auto-trading (only after dry-run validation)

Once you've watched the panel for a few sessions and you're satisfied with the analysis quality:

1. Right-click the chart → *Expert Advisors → Properties*.
2. Set `InpAutoTrade = true`.
3. **Test on a demo account first.** The bot will start placing trades whenever a valid setup with confidence ≥ `InpMinConfidence` and R/R ≥ `InpMinRR` appears.

## Step 9 — Backtesting in the Strategy Tester

1. In MT5, press **Ctrl+R** (or *View → Strategy Tester*).
2. *Expert*: select `ElliottWaveBot`.
3. *Symbol* / *Period* of your choice.
4. Choose a date range covering at least 6 months of data.
5. Set `InpAutoTrade = true` in the inputs tab.
6. Click *Start*.

The Strategy Tester will replay history bar by bar, executing trades when valid setups appear. Inspect the trade log and equity curve in the *Results* tab.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| 0 errors but the EA doesn't trade | `InpAutoTrade = false` | Set it to `true` |
| Compile error: "cannot open source file" | Include path wrong | Verify `MQL5\Include\ElliottWave\*.mqh` is in place |
| EA loads but panel says "No count" | Not enough pivots | Lower `InpZZDepth` or `InpZZDeviation` |
| Confidence permanently 0 | Cardinal rule broken on the count | Inspect R1/R2/R3 in the panel — that count is invalid |
| Lot size = 0 | SL distance is 0 or below broker minimum | Increase `InpSLBufferPoints` |
| `OrderSend error 10016: Invalid stops` | SL/TP too close to current price | Broker stops level — increase `InpSLBufferPoints` |
