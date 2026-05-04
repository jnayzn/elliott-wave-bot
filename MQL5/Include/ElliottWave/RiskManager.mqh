//+------------------------------------------------------------------+
//|                                                RiskManager.mqh  |
//|                              Elliott Wave Bot — Position sizing |
//+------------------------------------------------------------------+
#property copyright "Elliott Wave Bot"
#property strict
#ifndef __EWB_RISK_MANAGER_MQH__
#define __EWB_RISK_MANAGER_MQH__

//+------------------------------------------------------------------+
//|  Compute lot size for a trade where:                             |
//|    - risk_percent is the % of `balance` we are willing to lose   |
//|    - sl_distance  is the absolute price distance to the SL       |
//|    - tick_value   is the value (in account currency) of one tick |
//|    - tick_size    is the smallest tradeable price increment      |
//+------------------------------------------------------------------+
double EwbComputeLotSize(const double balance,
                         const double risk_percent,
                         const double sl_distance,
                         const double tick_value,
                         const double tick_size,
                         const double volume_min,
                         const double volume_max,
                         const double volume_step)
{
   if(balance <= 0.0 || risk_percent <= 0.0) return 0.0;
   if(sl_distance <= 0.0 || tick_value <= 0.0 || tick_size <= 0.0) return 0.0;

   double risk_money = balance * (risk_percent / 100.0);
   double money_per_lot_per_point = tick_value / tick_size;
   double lots = risk_money / (sl_distance * money_per_lot_per_point);

   if(lots < volume_min) lots = volume_min;
   if(lots > volume_max) lots = volume_max;

   if(volume_step > 0.0)
   {
      double steps = MathFloor(lots / volume_step);
      lots = steps * volume_step;
   }
   if(lots < volume_min) lots = volume_min;
   return lots;
}

bool EwbMeetsMinRR(const double rr, const double min_rr)
{
   return (rr >= min_rr);
}

bool EwbMeetsMinConfidence(const int confidence, const int min_conf)
{
   return (confidence >= min_conf);
}

#endif // __EWB_RISK_MANAGER_MQH__
