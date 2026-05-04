//+------------------------------------------------------------------+
//|                                                   HUDPanel.mqh  |
//|                                      Elliott Wave Bot — On-chart|
//+------------------------------------------------------------------+
//|  Draws the on-chart HUD panel + wave labels + Entry/SL/TP lines  |
//|  matching the layout of the reference screenshot.                |
//|                                                                  |
//|  Object naming convention: every object is prefixed with a tag   |
//|  derived from a constructor argument so the panel can be safely  |
//|  cleaned on de-init without nuking unrelated objects.            |
//+------------------------------------------------------------------+
#property copyright "Elliott Wave Bot"
#property strict
#ifndef __EWB_HUD_PANEL_MQH__
#define __EWB_HUD_PANEL_MQH__

#include "WaveCounter.mqh"
#include "TradeSetup.mqh"

//+------------------------------------------------------------------+
//|  HUD configuration / colours.                                    |
//+------------------------------------------------------------------+
struct EwbHUDConfig
{
   string  prefix;
   int     x;
   int     y;
   int     width;
   int     line_height;
   int     font_size;
   string  font_name;
   color   bg_color;
   color   header_color;
   color   header_text;
   color   label_color;
   color   value_color;
   color   good_color;
   color   bad_color;
   color   warn_color;
   color   wave_impulse_color;
   color   wave_correction_color;
   color   entry_color;
   color   sl_color;
   color   tp_color;
};

void EwbDefaultHUDConfig(EwbHUDConfig &cfg, const string prefix = "EWB_")
{
   cfg.prefix      = prefix;
   cfg.x           = 12;
   cfg.y           = 32;
   cfg.width       = 360;
   cfg.line_height = 16;
   cfg.font_size   = 9;
   cfg.font_name   = "Consolas";
   cfg.bg_color              = clrBlack;
   cfg.header_color          = C'40,40,40';
   cfg.header_text           = clrYellow;
   cfg.label_color           = clrSilver;
   cfg.value_color           = clrWhite;
   cfg.good_color            = clrLime;
   cfg.bad_color             = clrRed;
   cfg.warn_color            = clrGold;
   cfg.wave_impulse_color    = clrDodgerBlue;
   cfg.wave_correction_color = clrMediumPurple;
   cfg.entry_color           = clrGold;
   cfg.sl_color              = clrCrimson;
   cfg.tp_color              = clrLime;
}

//+------------------------------------------------------------------+
//|  Internal helpers                                                |
//+------------------------------------------------------------------+
void EwbEnsureLabel(const string name, const EwbHUDConfig &cfg, const int x, const int y,
                    const string text, const color clr, const int font_size = 0)
{
   int fsz = (font_size > 0) ? font_size : cfg.font_size;
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
   ObjectSetString (0, name, OBJPROP_FONT, cfg.font_name);
}

void EwbEnsureRectLabel(const string name, const EwbHUDConfig &cfg, const int x, const int y,
                        const int width, const int height, const color bg)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'80,80,80');
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

void EwbEnsureButton(const string name, const EwbHUDConfig &cfg, const int x, const int y,
                     const int width, const int height, const string text, const color bg, const color text_clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'120,120,120');
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, cfg.font_size);
      ObjectSetString (0, name, OBJPROP_FONT, cfg.font_name);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_clr);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
}

void EwbEnsureChartText(const string name, const EwbHUDConfig &cfg,
                        const datetime t, const double price,
                        const string text, const color clr,
                        const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_LOWER)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble (0, name, OBJPROP_PRICE, price);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, cfg.font_size + 2);
   ObjectSetString (0, name, OBJPROP_FONT, cfg.font_name);
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

//+------------------------------------------------------------------+
//|  Cleanup all objects bearing this prefix.                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//|  Direction text + colour helpers.                                |
//+------------------------------------------------------------------+
string EwbDirectionText(const EwbWaveDirection d)
{
   if(d == EWB_WAVE_DIR_BULLISH) return "BULLISH";
   if(d == EWB_WAVE_DIR_BEARISH) return "BEARISH";
   return "-";
}

color EwbDirectionColor(const EwbWaveDirection d, const EwbHUDConfig &cfg)
{
   if(d == EWB_WAVE_DIR_BULLISH) return cfg.good_color;
   if(d == EWB_WAVE_DIR_BEARISH) return cfg.bad_color;
   return cfg.label_color;
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

//+------------------------------------------------------------------+
//|  Render the textual HUD panel.                                   |
//+------------------------------------------------------------------+
void EwbRenderPanel(const EwbHUDConfig &cfg,
                    const string symbol,
                    const ENUM_TIMEFRAMES tf,
                    const datetime updated,
                    const EwbWaveCount &wc,
                    const EwbTradeSetup &ts)
{
   const int x  = cfg.x;
   const int y  = cfg.y;
   const int w  = cfg.width;
   const int lh = cfg.line_height;
   const string p = cfg.prefix;

   EwbEnsureRectLabel(p + "bg",     cfg, x, y, w, lh * 22 + 10, cfg.bg_color);
   EwbEnsureRectLabel(p + "header", cfg, x, y, w - 70, lh + 6, cfg.header_color);
   EwbEnsureLabel    (p + "title",  cfg, x + 8, y + 4, "Elliott Wave Analyzer", cfg.header_text, cfg.font_size + 1);
   EwbEnsureButton   (p + "sync_btn", cfg, x + w - 60, y + 2, 56, lh + 2, "SYNC", clrGoldenrod, clrBlack);

   int row = y + lh + 12;
   string tf_str = EnumToString(tf);

   EwbEnsureLabel(p + "lab_sym", cfg, x + 8,  row, "Symbol:",   cfg.label_color);
   EwbEnsureLabel(p + "val_sym", cfg, x + 90, row, symbol,      cfg.value_color);
   row += lh;

   EwbEnsureLabel(p + "lab_tf",  cfg, x + 8,  row, "Timeframe:", cfg.label_color);
   EwbEnsureLabel(p + "val_tf",  cfg, x + 90, row, tf_str,       cfg.value_color);
   row += lh;

   EwbEnsureLabel(p + "lab_upd", cfg, x + 8,  row, "Updated:",   cfg.label_color);
   EwbEnsureLabel(p + "val_upd", cfg, x + 90, row, TimeToString(updated, TIME_DATE | TIME_MINUTES), cfg.value_color);
   row += lh;

   EwbEnsureLabel(p + "lab_st",  cfg, x + 8,  row, "Status:",    cfg.label_color);
   EwbEnsureLabel(p + "val_st",  cfg, x + 90, row, EwbStatusText(wc.status), cfg.value_color);
   row += lh + 4;

   EwbEnsureLabel(p + "wc_hdr", cfg, x + 8, row, "WAVE COUNT", cfg.warn_color);
   row += lh;

   EwbEnsureLabel(p + "lab_note", cfg, x + 16, row, wc.note, cfg.value_color);
   row += lh;

   EwbEnsureLabel(p + "lab_dir", cfg, x + 16, row, "Direction:",  cfg.label_color);
   EwbEnsureLabel(p + "val_dir", cfg, x + 110, row, EwbDirectionText(wc.direction), EwbDirectionColor(wc.direction, cfg));
   row += lh;

   string bar = "";
   int filled = (int)MathRound(wc.confidence / 10.0);
   if(filled < 0)  filled = 0;
   if(filled > 10) filled = 10;
   for(int i = 0; i < 10; ++i) bar += (i < filled ? "#" : "-");
   EwbEnsureLabel(p + "lab_cf",  cfg, x + 16, row, "Confidence:", cfg.label_color);
   EwbEnsureLabel(p + "val_cf",  cfg, x + 110, row,
                  StringFormat("[%s] %d/100", bar, wc.confidence),
                  (wc.confidence >= 70 ? cfg.good_color :
                   wc.confidence >= 40 ? cfg.warn_color : cfg.bad_color));
   row += lh;

   EwbEnsureLabel(p + "lab_bias", cfg, x + 16, row, "Bias:",      cfg.label_color);
   EwbEnsureLabel(p + "val_bias", cfg, x + 110, row, EwbDirectionText(wc.bias), EwbDirectionColor(wc.bias, cfg));
   row += lh + 4;

   EwbEnsureLabel(p + "ts_hdr", cfg, x + 8, row, "TRADE SETUP", cfg.warn_color);
   row += lh;

   if(ts.valid)
   {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      EwbEnsureLabel(p + "lab_e",  cfg, x + 16, row, "Entry:", cfg.label_color);
      EwbEnsureLabel(p + "val_e",  cfg, x + 110, row, DoubleToString(ts.entry, digits), cfg.entry_color);
      row += lh;
      EwbEnsureLabel(p + "lab_sl", cfg, x + 16, row, "SL:",    cfg.label_color);
      EwbEnsureLabel(p + "val_sl", cfg, x + 110, row, DoubleToString(ts.sl, digits), cfg.sl_color);
      row += lh;
      EwbEnsureLabel(p + "lab_t1", cfg, x + 16, row, "TP1:",   cfg.label_color);
      EwbEnsureLabel(p + "val_t1", cfg, x + 110, row, DoubleToString(ts.tp1, digits), cfg.tp_color);
      row += lh;
      EwbEnsureLabel(p + "lab_t2", cfg, x + 16, row, "TP2:",   cfg.label_color);
      EwbEnsureLabel(p + "val_t2", cfg, x + 110, row, DoubleToString(ts.tp2, digits), cfg.tp_color);
      row += lh;
      EwbEnsureLabel(p + "lab_t3", cfg, x + 16, row, "TP3:",   cfg.label_color);
      EwbEnsureLabel(p + "val_t3", cfg, x + 110, row, DoubleToString(ts.tp3, digits), cfg.tp_color);
      row += lh;
      EwbEnsureLabel(p + "lab_rr", cfg, x + 16, row, "R/R:",   cfg.label_color);
      EwbEnsureLabel(p + "val_rr", cfg, x + 110, row, DoubleToString(ts.rr, 2),
                     (ts.rr >= 2.0 ? cfg.good_color : ts.rr >= 1.0 ? cfg.warn_color : cfg.bad_color));
   }
   else
   {
      EwbEnsureLabel(p + "lab_e", cfg, x + 16, row, "No setup",  cfg.label_color);
      row += lh;
   }
   row += lh + 4;

   EwbEnsureLabel(p + "rule_hdr", cfg, x + 8, row, "ELLIOTT RULES", cfg.warn_color);
   row += lh;

   EwbEnsureLabel(p + "lab_r1", cfg, x + 16, row, "R1 W2<=W1:", cfg.label_color);
   EwbEnsureLabel(p + "val_r1", cfg, x + 130, row,
                  wc.rule_w2_no_full_retrace ? "YES" : "NO",
                  wc.rule_w2_no_full_retrace ? cfg.good_color : cfg.bad_color);
   row += lh;

   EwbEnsureLabel(p + "lab_r2", cfg, x + 16, row, "R2 W3 not short:", cfg.label_color);
   EwbEnsureLabel(p + "val_r2", cfg, x + 130, row,
                  wc.rule_w3_not_shortest ? "YES" : "NO",
                  wc.rule_w3_not_shortest ? cfg.good_color : cfg.bad_color);
   row += lh;

   EwbEnsureLabel(p + "lab_r3", cfg, x + 16, row, "R3 W4!=W1 zone:", cfg.label_color);
   EwbEnsureLabel(p + "val_r3", cfg, x + 130, row,
                  wc.rule_w4_no_overlap ? "YES" : "NO",
                  wc.rule_w4_no_overlap ? cfg.good_color : cfg.bad_color);
   row += lh + 4;

   EwbEnsureLabel(p + "notes_hdr", cfg, x + 8, row, "NOTES", cfg.warn_color);
}

//+------------------------------------------------------------------+
//|  Draw the wave-count overlay (numbered 1-5 + ABC labels and      |
//|  connecting trend lines) on the chart.                           |
//+------------------------------------------------------------------+
void EwbRenderWaveOverlay(const EwbHUDConfig &cfg, const EwbWaveCount &wc)
{
   string p = cfg.prefix + "wv_";

   if(wc.direction != EWB_WAVE_DIR_NONE)
   {
      EwbEnsureTrendLine(p + "01", wc.p0.time, wc.p0.price, wc.p1.time, wc.p1.price,
                         cfg.wave_impulse_color, 2);
      EwbEnsureTrendLine(p + "12", wc.p1.time, wc.p1.price, wc.p2.time, wc.p2.price,
                         cfg.wave_impulse_color, 2);
      EwbEnsureTrendLine(p + "23", wc.p2.time, wc.p2.price, wc.p3.time, wc.p3.price,
                         cfg.wave_impulse_color, 2);

      EwbEnsureChartText(p + "lbl1", cfg, wc.p1.time, wc.p1.price, "1", cfg.wave_impulse_color,
                         (wc.direction == EWB_WAVE_DIR_BULLISH ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER));
      EwbEnsureChartText(p + "lbl2", cfg, wc.p2.time, wc.p2.price, "2", cfg.wave_impulse_color,
                         (wc.direction == EWB_WAVE_DIR_BULLISH ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER));
      EwbEnsureChartText(p + "lbl3", cfg, wc.p3.time, wc.p3.price, "3", cfg.wave_impulse_color,
                         (wc.direction == EWB_WAVE_DIR_BULLISH ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER));
   }
   if(wc.status >= EWB_WAVE_STATUS_IMPULSE_DONE)
   {
      EwbEnsureTrendLine(p + "34", wc.p3.time, wc.p3.price, wc.p4.time, wc.p4.price,
                         cfg.wave_impulse_color, 2);
      EwbEnsureTrendLine(p + "45", wc.p4.time, wc.p4.price, wc.p5.time, wc.p5.price,
                         cfg.wave_impulse_color, 2);
      EwbEnsureChartText(p + "lbl4", cfg, wc.p4.time, wc.p4.price, "4", cfg.wave_impulse_color,
                         (wc.direction == EWB_WAVE_DIR_BULLISH ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER));
      EwbEnsureChartText(p + "lbl5", cfg, wc.p5.time, wc.p5.price, "5", cfg.wave_impulse_color,
                         (wc.direction == EWB_WAVE_DIR_BULLISH ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER));
   }
   if(wc.status >= EWB_WAVE_STATUS_ABC_FORMING)
   {
      EwbEnsureTrendLine(p + "5A", wc.p5.time, wc.p5.price, wc.pA.time, wc.pA.price,
                         cfg.wave_correction_color, 2, STYLE_SOLID);
      EwbEnsureChartText(p + "lblA", cfg, wc.pA.time, wc.pA.price, "A", cfg.wave_correction_color,
                         (wc.direction == EWB_WAVE_DIR_BULLISH ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER));
   }
   if(wc.status >= EWB_WAVE_STATUS_ABC_COMPLETE)
   {
      EwbEnsureTrendLine(p + "AB", wc.pA.time, wc.pA.price, wc.pB.time, wc.pB.price,
                         cfg.wave_correction_color, 2, STYLE_SOLID);
      EwbEnsureTrendLine(p + "BC", wc.pB.time, wc.pB.price, wc.pC.time, wc.pC.price,
                         cfg.wave_correction_color, 2, STYLE_SOLID);
      EwbEnsureChartText(p + "lblB", cfg, wc.pB.time, wc.pB.price, "B", cfg.wave_correction_color,
                         (wc.direction == EWB_WAVE_DIR_BULLISH ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER));
      EwbEnsureChartText(p + "lblC", cfg, wc.pC.time, wc.pC.price, "C", cfg.wave_correction_color,
                         (wc.direction == EWB_WAVE_DIR_BULLISH ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER));
   }
}

//+------------------------------------------------------------------+
//|  Render the entry / SL / TP horizontal lines.                   |
//+------------------------------------------------------------------+
void EwbRenderTradeLines(const EwbHUDConfig &cfg, const EwbTradeSetup &ts)
{
   string p = cfg.prefix + "tl_";
   if(!ts.valid)
   {
      ObjectDelete(0, p + "entry");
      ObjectDelete(0, p + "sl");
      ObjectDelete(0, p + "tp1");
      ObjectDelete(0, p + "tp2");
      ObjectDelete(0, p + "tp3");
      return;
   }
   EwbEnsureHLine(p + "entry", ts.entry, cfg.entry_color, 1, STYLE_DASHDOT);
   EwbEnsureHLine(p + "sl",    ts.sl,    cfg.sl_color,    1, STYLE_DASH);
   EwbEnsureHLine(p + "tp1",   ts.tp1,   cfg.tp_color,    1, STYLE_DASH);
   EwbEnsureHLine(p + "tp2",   ts.tp2,   cfg.tp_color,    1, STYLE_DASH);
   EwbEnsureHLine(p + "tp3",   ts.tp3,   cfg.tp_color,    1, STYLE_DASH);
}

#endif // __EWB_HUD_PANEL_MQH__
