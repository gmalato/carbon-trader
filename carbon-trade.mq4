//+------------------------------------------------------------------+
//|                                               carbon_trader.mq4  |
//|                              Copyright 2023, gmalato@hotmail.com |
//|                                        https://gmalato.github.io |
//+------------------------------------------------------------------+

#property copyright "Copyright © 2023, gmalato@hotmail.com"
#property description "Copy trades between termninals"
#property version "1.2"

#property strict

enum copier_mode {master, slave};

input copier_mode mode = 1;  // Mode: use 0 for master, 1 for slave
input double mult = 1.0; // Slave multiplier
input int slip = 0; // Slippage PIPs: use 0 to disable

int opened_list[500], ticket, type, filehandle;
string symbol;
double lot, price, sl, tp;

bool clean_deinit = true;
string tag = "20230614-1";

/**
 * Initializes the EA; should be replace by the newer OnInit()
 * 
 */

void init() {
    Print("Carbon Trade ", tag);

    // if the EA was started in master mode, make sure no other master is 
    // already running

    if (EnumToString(mode) == "master" ) {
        if (FileIsExist("master.ct4", FILE_COMMON)) {
            Print("A master is already running, removing EA");

            // skip master file check during deinit
            clean_deinit = false;

            ExpertRemove();
        } else {
            filehandle = FileOpen("master.ct4", FILE_WRITE | FILE_CSV | FILE_COMMON);
            FileWrite(filehandle, AccountInfoInteger(ACCOUNT_LOGIN));
            FileClose(filehandle);
        }
    }

    ObjectsDeleteAll();
    EventSetTimer(1);
    return;
}

/**
 * Initializes the EA; should be replace by the newer OnDeinit()
 * 
 */

void deinit() {
    ObjectsDeleteAll();
    EventKillTimer();

    if (EnumToString(mode) == "master" && clean_deinit) {
        if (FileIsExist("master.ct4", FILE_COMMON)) {
            if (FileDelete("master.ct4", FILE_COMMON)) {
                Print("Master file removed");
            } else {
                Print("Master file not found");
            }
        } 
    }
    return;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

void OnTimer() {
    Comment(EnumToString(mode), " m:", mult, " s: ", slip, " t: ", tag);

//--- Master working mode
    if(EnumToString(mode)=="master")
       {
        //--- Saving information about opened deals
        if(OrdersTotal()==0)
           {
            filehandle=FileOpen("C4F.csv", FILE_WRITE|FILE_CSV|FILE_COMMON);
            FileWrite(filehandle, "");
            FileClose(filehandle);
           }
        else
           {
            filehandle=FileOpen("C4F.csv", FILE_WRITE|FILE_CSV|FILE_COMMON);

            if(filehandle!=INVALID_HANDLE)
               {
                for(int i=0; i<OrdersTotal(); i++)
                   {
                    if(!OrderSelect(i, SELECT_BY_POS))
                        break;
                    symbol=OrderSymbol();

                    if(StringSubstr(OrderComment(), 0, 3)!="C4F")
                        FileWrite(filehandle, OrderTicket(), symbol, OrderType(), OrderOpenPrice(), OrderLots(), OrderStopLoss(), OrderTakeProfit());
                    FileFlush(filehandle);
                   }
                FileClose(filehandle);
               }
           }
       }

    // slave working mode
    if(EnumToString(mode) == "slave") {
        // check for new positions and SL/TP changes
        filehandle = FileOpen("C4F.csv", FILE_READ|FILE_CSV|FILE_COMMON);

        if(filehandle!=INVALID_HANDLE)
           {
            int o=0;
            opened_list[o]=0;

            while(!FileIsEnding(filehandle))
               {
                ticket=StrToInteger(FileReadString(filehandle));
                symbol=FileReadString(filehandle);
                type=StrToInteger(FileReadString(filehandle));
                price=StrToDouble(FileReadString(filehandle));
                lot=StrToDouble(FileReadString(filehandle))*mult;
                sl=StrToDouble(FileReadString(filehandle));
                tp=StrToDouble(FileReadString(filehandle));

                string
                OrdComm="C4F"+IntegerToString(ticket);

                for(int i=0; i<OrdersTotal(); i++)
                   {
                    if(!OrderSelect(i, SELECT_BY_POS))
                        continue;

                    if(OrderComment()!=OrdComm)
                        continue;

                    opened_list[o]=ticket;
                    opened_list[o+1]=0;
                    o++;

                    if(OrderType() > 1 && OrderOpenPrice() != price)
                       {
                        if(!OrderModify(OrderTicket(), price, 0, 0, 0))
                            Print("Error: ", GetLastError(), " during modification of the order.");
                       }

                    if(tp!=OrderTakeProfit() || sl!=OrderStopLoss())
                       {
                        if(!OrderModify(OrderTicket(), OrderOpenPrice(), sl, tp, 0))
                            Print("Error: ", GetLastError(), " during modification of the order.");
                       }
                    break;
                   }

                //--- If deal was not opened yet on slave-account, open it.
                if(InList(ticket)==-1 && ticket!=0)
                   {
                    FileClose(filehandle);
                    if(type<2)
                        OpenMarketOrder(ticket, symbol, type, price, lot);
                    if(type>1)
                        OpenPendingOrder(ticket, symbol, type, price, lot);
                    return;
                   }
               }
            FileClose(filehandle);
           }
        else
            return;

        // if a position was closed on the master account, close it on the slave
        for(int i = 0; i < OrdersTotal(); i++) {
            if(!OrderSelect(i, SELECT_BY_POS))
                continue;

            if(StringSubstr(OrderComment(), 0, 3) != "C4F")  // TODO: Watch this! :)
                continue;

            if(InList(StrToInteger(StringSubstr(OrderComment(), StringLen("C4F"), 0))) == -1) {
                if(OrderType() == 0) {
                    if(!OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_BID), slip))
                        Print("Error: ", GetLastError(), " during closing the order.");
                   }
                else
                    if(OrderType() == 1)
                       {
                        if(!OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_ASK), slip))
                            Print("Error: ", GetLastError(), " during closing the order.");
                       }
                    else
                        if(OrderType()>1)
                           {
                            if(!OrderDelete(OrderTicket()))
                                Print("Error: ", GetLastError(), " during deleting the pending order.");
                           }
               }
           }
       }
   }


//+------------------------------------------------------------------+
//|Checking list                                                     |
//+------------------------------------------------------------------+
int InList(int ticket_)
   {
    int h=0;

    while(opened_list[h]!=0)
       {
        if(opened_list[h]==ticket_)
            return(1);
        h++;
       }
    return(-1);
   }
//+------------------------------------------------------------------+
//|Open market execution orders                                      |
//+------------------------------------------------------------------+
void OpenMarketOrder(int ticket_, string symbol_, int type_, double price_, double lot_)
   {
    double market_price = MarketInfo(symbol_, MODE_BID);
    if(type_== 0)
        market_price = MarketInfo(symbol_, MODE_ASK);

    double delta;
    double gmMarketInfo = MarketInfo(symbol_, MODE_POINT);

    if(gmMarketInfo <= 0)
       {
        Print("Warning: ", symbol_, "MODE_POINT = ", gmMarketInfo);
        gmMarketInfo = 1;
       }

    delta = MathAbs(market_price - price_) / gmMarketInfo;
    if(slip > 0 && delta > slip)
       {
        Print("An order was not copied because of slippage");
        return;
       }

    if(!OrderSend(symbol_, type_, LotNormalize(lot_), market_price, slip, 0, 0, "C4F" + IntegerToString(ticket_)))
        Print("Error: ", GetLastError(), " during opening the market order.");

    return;

   }

//+------------------------------------------------------------------+
//|Open pending orders                                               |
//+------------------------------------------------------------------+
void OpenPendingOrder(int ticket_, string symbol_, int type_, double price_, double lot_)
   {
    if(!OrderSend(symbol_, type_, LotNormalize(lot_), price_, slip, 0, 0, "C4F"+IntegerToString(ticket_)))
        Print("Error: ", GetLastError(), " during setting the pending order.");
    return;
   }
//+------------------------------------------------------------------+
//|Normalize lot size                                                |
//+------------------------------------------------------------------+
double LotNormalize(double lot_)
   {
    double minlot=MarketInfo(symbol, MODE_MINLOT);

    if(minlot==0.001)
        return(NormalizeDouble(lot_, 3));
    else
        if(minlot==0.01)
            return(NormalizeDouble(lot_, 2));
        else
            if(minlot==0.1)
                return(NormalizeDouble(lot_, 1));

    return(NormalizeDouble(lot_, 0));
   }
//+------------------------------------------------------------------+
