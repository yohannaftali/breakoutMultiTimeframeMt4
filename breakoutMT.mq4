//+------------------------------------------------------------------+
//|                                         Breakout Multi Timeframe |
//|                                    Copyright 2024, Yohan Naftali |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Yohan Naftali"
#property link      "https://github.com/yohannaftali"
#property version   "240.725"
#property strict

//--- input parameters
input string beginOrderString = "07:00";        // Start Order Time (hh:mm) (Server Time)
input string endOrderString = "15:59";          // End Order Time (hh:mm) (Server Time)
input ENUM_TIMEFRAMES period = PERIOD_H1;       // Period
input double stopLossPip = 1.6;                 // Stop Loss (pip)
input double riskPercentage = 1;                // Stop loss Risk (%)
input double rewardRiskRatio = 10;              // Target Profit Reward/Risk Ratio
input ENUM_TIMEFRAMES zigZagPeriod = PERIOD_H4; // Period ZigZag
input int zigZagDepth = 12;                     // Depth
input int zigZagDeviation =5;                   // Deviation
input int zigZagBackstep = 3;                   // Backstep
input double offsetPip = -2;                    // Offset Upper/Lower From S/R (pip)
input int slippage = 2;                         // Slippage points (Usually specified as 0-3 points)
input int magicNumber = 1;                      // EA's MagicNumber

//--- global variable
double support, resistance;
int lastTotalOpenOrder, pipToPoint, digitVolume;
double stopLevelPrice, offsetPrice;
double stopLossPrice, takeProfitMargin;
double minVolume, maxVolume, lotStep, volumeLotPerRisk;

color upperClr = Blue;
color lowerClr = Red;
int lineStyle = STYLE_SOLID;
int lineWidth = 1;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
  initVariable();

  datetime current = TimeCurrent();
  datetime gmt = TimeGMT();
  datetime local = TimeLocal();

  Print("# ----------------------------------");
  Print("# Symbol Specification Info");
  Print("- Symbol: " + Symbol());
  Print("- Minimum Lot: " + DoubleToString(minVolume, digitVolume));
  Print("- Maximum Lot: " + DoubleToString(maxVolume, digitVolume));
  Print("- Stop Level: " + DoubleToString(stopLevelPrice, Digits()));

  Print("# Time Info");
  Print("- Current Time: " + TimeToString(current));
  Print("- GMT Time: " + TimeToString(gmt));
  Print("- Local Time: " + TimeToString(local));

  Print("# Trading Window");
  Print("- Start Trading Time: " + beginOrderString);
  Print("- End Trading Time: " + endOrderString);
  Print("- Timeframe Period: " + EnumToString(period));

  Print("# Risk Management Info");
  Print("- Stop Loss: " + DoubleToString(stopLossPip) + " Pip");
  Print("- S/L Risk Percentage: " + DoubleToString(riskPercentage, 2) + "%");
  Print("- T/P Reward/Risk Ratio: " + DoubleToString(rewardRiskRatio, 2));

  Print("# S/R Line with ZigZag");
  Print("- Depth: " + IntegerToString(zigZagDepth));
  Print("- Deviation: " + IntegerToString(zigZagDeviation));
  Print("- Backstep: " + IntegerToString(zigZagBackstep));
  Print("- Offset from S/R Line:" + DoubleToString(offsetPip, 2) + " Pip");

  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  EventKillTimer();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
  int currentTotalOpenOrder = totalOpenOrder();
  if(currentTotalOpenOrder != lastTotalOpenOrder) {
    if(currentTotalOpenOrder == 0) {
      closeAllPendingOrders();
      showLastTrade();
    }
    lastTotalOpenOrder = currentTotalOpenOrder;
  }

  updateTrailingStop();


  if(!isNewBar()) return;

  setupOrder();
}

//+------------------------------------------------------------------+
//| Clear All Pending Order                                                                 |
//+------------------------------------------------------------------+
void showLastTrade()
{
  for(int i = (OrdersTotal() - 1); i >= 0; i--) {
    if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
    if(OrderSymbol() != Symbol()) continue;
    if(OrderMagicNumber() != magicNumber ) continue;
    if(!(OrderType() == OP_BUY || OrderType() == OP_SELL)) continue;
    int ticket = OrderTicket();
    double currentProfit = OrderProfit() + OrderSwap() + OrderCommission();
    Print("Order #" + IntegerToString(ticket) + " Profit: " + DoubleToString(currentProfit, 2));
  }
}

//+------------------------------------------------------------------+
//| Setup order if new bar is detected                               |
//+------------------------------------------------------------------+
void setupOrder()
{
  // Skip if still have position
  if(totalOpenOrder() > 0) return;

  // Close all pending order first
  closeAllPendingOrders();

  // Skip is not trading time
  if(!isTradingTime() ) return;

  calculateSupportResistance();

  double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK); // Best Buy Offer
  double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID); // Best Sell Offer

  Print("Ask: " + DoubleToString(ask, Digits()));
  Print("Bid: " + DoubleToString(bid, Digits()));
  Print("Support: " + DoubleToString(support, Digits()));
  Print("Resitance: " + DoubleToString(resistance, Digits()));

  if(support <= 0 || resistance <= 0 || resistance <= support) return;
  calculateStopLevel();
  double volume = calculateVolume();
  handleBuy(ask, volume);
  handleSell(bid, volume);

}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void handleBuy(double ask, double volume)
{
  double priceBuy = resistance + offsetPrice;
  priceBuy = NormalizeDouble(priceBuy, Digits());

  if(ask > priceBuy) return;
  if((priceBuy - ask) < stopLevelPrice) return;

  double slBuy = priceBuy - stopLossPrice;
  double tpBuy = priceBuy + takeProfitMargin;
  tpBuy = NormalizeDouble(tpBuy, Digits());
  //double tpBuy = 0;

  string commentBuy = "Buy Stop " + DoubleToString(priceBuy, Digits()) + " #" + IntegerToString(magicNumber);

  int ticketBuy = OrderSend(Symbol(), OP_BUYSTOP, volume, priceBuy, slippage, slBuy, tpBuy, commentBuy, magicNumber, 0, clrGreen);
  if(!ticketBuy) {
    Print("OrderSend Buy Stop failed with error #", GetLastError());
  }

  Print("Send order buy stop successfully");
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void handleSell(double bid, double volume)
{
  double priceSell = support - offsetPrice;
  priceSell = NormalizeDouble(priceSell, Digits());

  if(bid < priceSell) return;
  if((bid - priceSell) < stopLevelPrice) return;

  double slSell = priceSell + stopLossPrice;
  double tpSell = priceSell - takeProfitMargin;
  tpSell = NormalizeDouble(tpSell, Digits());
  //double tpSell = 0;

  string commentSell = "Sell Stop " + DoubleToString(priceSell, Digits()) + " #" + IntegerToString(magicNumber);

  int ticketSell = OrderSend(Symbol(), OP_SELLSTOP, volume, priceSell, slippage, slSell, tpSell, commentSell, magicNumber, 0, clrRed);
  if(!ticketSell) {
    Print("OrderSend Sell Stop failed with error #", GetLastError());
    return;
  }

  Print("Send order sell stop successfully");
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void updateTrailingStop()
{
  if(totalOpenOrder() == 0) return;

  for(int i = (OrdersTotal() - 1); i >= 0; i--) {
    if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
    if(OrderSymbol() != Symbol()) continue;
    if(OrderMagicNumber() != magicNumber ) continue;
    int orderType = OrderType();
    if(orderType >= 2) continue;
    int ticket = OrderTicket();

    double currentStopLoss = OrderStopLoss();

    if(orderType == OP_BUY) {
      double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID); // Best Sell Offer
      double slBuy = bid - stopLossPrice;
      if(slBuy > currentStopLoss) {
        double tpBuy = bid + (stopLossPrice * rewardRiskRatio);
        tpBuy = NormalizeDouble(tpBuy, Digits());
        //double tpBuy = 0;

        int modifiyBuy = OrderModify(ticket, OrderOpenPrice(), slBuy, tpBuy, 0, clrGreen);
        if(!modifiyBuy)
          Print("Error in OrderModify. Error code=", GetLastError());
        else
          Print("Order modified successfully.");
      }
    }
    if(orderType == OP_SELL) {
      double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK); // Best Buy Offer
      double slSell = ask + stopLossPrice;
      if(slSell < currentStopLoss) {
        double tpSell = ask - (stopLossPrice * rewardRiskRatio);
        tpSell = NormalizeDouble(tpSell, Digits());
        //double tpSell = 0;

        int modifiySell = OrderModify(ticket, OrderOpenPrice(), slSell, tpSell, 0, clrGreen);
        if(!modifiySell)
          Print("Error in OrderModify. Error code=", GetLastError());
        else
          Print("Order modified successfully.");
      }
    }
  }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void calculateSupportResistance()
{
  int limit = 300;

  int indexHigh = 0;
  double a[3];
  int n = 0;
  for(int i = 0; i < limit; i++) {
    double z = iCustom(Symbol(), zigZagPeriod, "ZigZag", zigZagDepth, zigZagDeviation, zigZagBackstep, 0, i);
    if(z == 0) continue;
    if(z == EMPTY_VALUE) break;
    a[n] = z;
    n++;
    if(n >= 3) break;
  }

  double x = a[0] ? a[0] : 0;
  double y = a[1] ? a[1] : 0;
  double z = a[2] ? a[2] : 0;
  if((x > y && y > z) || (x < y && y < z)) {
    x = z;
  }
  support = x < y ? x : y;
  support = NormalizeDouble(support, Digits());
  resistance = x > y ? x : y;
  resistance = NormalizeDouble(resistance, Digits());

  Print("# S/R Line");
  Print("- Support: " + DoubleToString(support, Digits()));
  Print("- Resistance: " + DoubleToString(resistance, Digits()));

  drawSupport();
  drawSupportBreakout();
  drawResistance();
  drawResistanceBreakout();
}

//+------------------------------------------------------------------+
//| Return whether current tick is a new bar                         |
//+------------------------------------------------------------------+
bool isNewBar()
{
  static datetime lastBar;
  return lastBar != (lastBar = iTime(Symbol(), period, 0));
}

//+------------------------------------------------------------------+
//| Get Total Order                                                                 |
//+------------------------------------------------------------------+
int totalOrder()
{
  int res = 0;
  for(int i = (OrdersTotal() - 1); i >= 0; i--) {
    if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
    if(OrderSymbol() != Symbol()) continue;
    if(OrderMagicNumber() != magicNumber ) continue;
    res++;
  }
  return res;
}

//+------------------------------------------------------------------+
//| Get Total Open Order / Total Position                                                                |
//+------------------------------------------------------------------+
int totalOpenOrder()
{
  int res = 0;
  for(int i = (OrdersTotal() - 1); i >= 0; i--) {
    if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
    if(OrderSymbol() != Symbol()) continue;
    if(OrderMagicNumber() != magicNumber ) continue;
    if(OrderType() >= 2) continue;
    res++;
  }
  return res;
}

//+------------------------------------------------------------------+
//| Get Total Pending Order                                                                 |
//+------------------------------------------------------------------+
int totalPendingOrder()
{
  int res = 0;
  for(int i = (OrdersTotal() - 1); i >= 0; i--) {
    if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
    if(OrderSymbol() != Symbol()) continue;
    if(OrderMagicNumber() != magicNumber ) continue;
    if(OrderType() < 2) continue;
    res++;
  }
  return res;
}

//+------------------------------------------------------------------+
//| Clear All Pending Order                                                                 |
//+------------------------------------------------------------------+
void closeAllPendingOrders()
{
  for(int i = (OrdersTotal() - 1); i >= 0; i--) {
    if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
    if(OrderSymbol() != Symbol()) continue;
    if(OrderMagicNumber() != magicNumber ) continue;
    if(OrderType() < 2) continue;
    int ticket = OrderTicket();
    if(!OrderDelete(ticket)) {
      Print("Fail to delete order #" + IntegerToString(ticket));
    }
  }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void initVariable()
{
  pipToPoint = Digits() % 2 == 1 ? 10 : 1;

  // Minimal indention in points from the current close price to place
  // Stop orders
  calculateStopLevel();

  initStopLoss();
  initTakeProfitMargin();
  initVolume();

  offsetPrice = offsetPip * pipToPoint * Point();
  offsetPrice = NormalizeDouble(offsetPrice, Digits());

  lastTotalOpenOrder = totalOpenOrder();
}

//+------------------------------------------------------------------+
//| Initialize Stop Loss Price                                       |
//+------------------------------------------------------------------+
void initStopLoss()
{
  // On a 4 digit broker a point == pip.
  // On a 5 digit broker a point is 1/10 pip.
  // Either you must adjust all your pip values when you move from a
  // 4 to a 5 broker or the EA must adjust.

  double stopLossPoint = stopLossPip * pipToPoint;
  stopLossPrice = stopLossPoint * Point();
  stopLossPrice = NormalizeDouble(stopLossPrice, Digits());
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void initTakeProfitMargin()
{
  takeProfitMargin = rewardRiskRatio * stopLossPrice;
  takeProfitMargin = NormalizeDouble(takeProfitMargin, Digits());
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void calculateStopLevel()
{
  int stopLevelPoint = (int) SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
  int spreadPoint = (int) SymbolInfoInteger(Symbol(), SYMBOL_SPREAD); // In Point
  Print("Spread: " + DoubleToString(spreadPoint, Digits()) + " Points");
  Print("StopLevel: " + DoubleToString(stopLevelPoint, Digits()) + " Points");

  if(stopLevelPoint < spreadPoint*3) {
    stopLevelPoint = spreadPoint*3;
  }
  stopLevelPrice = stopLevelPoint * Point();
  stopLevelPrice = NormalizeDouble(stopLevelPrice, Digits());
}

//+------------------------------------------------------------------+
//| Initialize Volume                                                |
//+------------------------------------------------------------------+
void initVolume()
{
  // Step = Minimal volume change step for deal execution
  double stepVolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

  // Digit for volume not for price
  digitVolume = getDigit(stepVolume);

  // Define min and max volume
  minVolume = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
  minVolume = NormalizeDouble(minVolume, digitVolume);
  maxVolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
  maxVolume = NormalizeDouble(maxVolume, digitVolume);

  lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

  double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
  double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE); // Minimal price change
  volumeLotPerRisk = tickSize/(stopLossPrice * tickValue);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double calculateVolume()
{
  double balance = AccountInfoDouble(ACCOUNT_BALANCE);
  double risk = balance * (riskPercentage / 100.0);
  double volumeLot = risk * volumeLotPerRisk;

  volumeLot = NormalizeDouble(volumeLot / lotStep, 0) * lotStep;
  volumeLot = volumeLot > maxVolume ? maxVolume : volumeLot;
  volumeLot = volumeLot < minVolume ? minVolume : volumeLot;

  return volumeLot;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int getDigit(double num)
{
  int d = 0;
  double p = 1;
  while(MathRound(num * p) / p != num) {
    p = MathPow(10, ++d);
  }
  return d;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool isTradingTime()
{
  if(beginOrderString == "" && endOrderString == "") {
    return true;
  }

  datetime beginOrderTime = StringToTime(beginOrderString);
  datetime endOrderTime = StringToTime(endOrderString);

  datetime currentTime = TimeCurrent();
  if(endOrderTime > beginOrderTime) {
    if(currentTime >= beginOrderTime && currentTime <= endOrderTime) {
      return true;
    }
    return false;
  }

  if(endOrderTime >= beginOrderTime) {
    return false;
  }

  // overlap time
  if(currentTime <= endOrderTime) {
    return true;
  }

  if(currentTime >= beginOrderTime) {
    return true;
  }

  return false;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void drawSupport()
{
  ObjectDelete(ChartID(),"LowerLine");
  ObjectCreate(ChartID(),"LowerLine", OBJ_HLINE, 0, 0, support);
  ObjectSet("LowerLine", OBJPROP_COLOR, clrBlue);
  ObjectSet("LowerLine", OBJPROP_WIDTH, 1);
  ObjectSet("LowerLine", OBJPROP_STYLE, STYLE_DOT);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void drawSupportBreakout()
{
  ObjectDelete(ChartID(),"LowerLinePrice");
  ObjectCreate(ChartID(),"LowerLinePrice", OBJ_HLINE, 0, 0, (support - offsetPrice) );
  ObjectSet("LowerLinePrice", OBJPROP_COLOR, clrBlue);
  ObjectSet("LowerLinePrice", OBJPROP_WIDTH, 1);
  ObjectSet("LowerLinePrice", OBJPROP_STYLE, STYLE_SOLID);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void drawResistance()
{
  ObjectDelete(ChartID(),"UpperLine");
  ObjectCreate(ChartID(),"UpperLine", OBJ_HLINE, 0, 0, resistance);
  ObjectSet("UpperLine",OBJPROP_COLOR, clrBlue);
  ObjectSet("UpperLine",OBJPROP_WIDTH, 1);
  ObjectSet("UpperLine",OBJPROP_STYLE, STYLE_DOT);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void drawResistanceBreakout()
{
  ObjectDelete(ChartID(),"UpperLinePrice");
  ObjectCreate(ChartID(),"UpperLinePrice", OBJ_HLINE, 0, 0, (resistance + offsetPrice) );
  ObjectSet("UpperLinePrice",OBJPROP_COLOR, clrBlue);
  ObjectSet("UpperLinePrice",OBJPROP_WIDTH, 1);
  ObjectSet("UpperLinePrice",OBJPROP_STYLE, STYLE_SOLID);
}

//+------------------------------------------------------------------+
