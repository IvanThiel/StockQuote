using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Communications as Comm;
using Toybox.System as Sys;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Math;
using Toybox.Application as App;
import Toybox.Application.Storage;


var GlobalTouched = -1;
var mW;
var mH;
var mSH;
var mSW;

const DEFAULT_SETTINGS =  "^AEX;^AMX;BTC-USD;EURUSD=X;^FTSE;^GDAXI;YM=F;NQ=F;^DJI;^IXIC;CL=F;GC=F;^N225;^HSI";

var _debug = false;
var _sound = false;          
var _public = true; 

/*

  Stock quotes from yahoo finance. 

  When you tap on the lower left corner of the upper right corner of the field. The quotes are updates immediately. They are also updated every 15 minutes.

  You can cycle through the symbols by tapping on the upper right and lower left corner.
  
  You need an active phone connection with internet. Quotes are supplies by the Yahoo finance API.

  Via the settings you can change the symbols. Use ';'' to seperate the symbols.
  Symbol lookup via:  https://finance.yahoo.com

    e.g. ^DJI;^IXIC;BTC-USD;GRMN
    for  Dow Jones Index, Nasdaq Index, BITCOIN and Garmin
  
  
  */

class StockQuoteView extends Ui.DataField {

    hidden var YMARGING      = 3;
    hidden var XMARGINGL     = 6;

    hidden var mConnectie    = false;
    hidden var mBlink        = false;
    hidden var mLastMinute   = 0;
    hidden var mLoading      = false;
    hidden var mLoadingCount = 0;
    hidden var mCurrentSymbol = 0;
    hidden var mFields       = 0;

    hidden var mSymbol        = null;
    hidden var mQuote         = null;
    hidden var mPrevQuote     = null;
    hidden var mQuoteStr      = null;
    hidden var mChange        = null;
    hidden var mChangeStr     = null;
    hidden var mUpdateT       = null;
    hidden var mFirstShow     = true;
    hidden var mShowQuotes    = 1;
    hidden var mLoadSymbol    = 0;
    hidden var mOffset        = 0;

    /******************************************************************
     * INIT 
     ******************************************************************/  
    function initialize() {
      try {
        DataField.initialize();  
        getSettings();
        //mBikeRadar = new AntPlus.BikeRadar(new CombiSpeedRadarListener()); 
      } catch (ex) {
        debug ("init error: "+ex.getErrorMessage());
      }         
    }

    function getSettings() {
      try {
         var s = Application.getApp().getProperty("symbols"); 


        if ((s==null) || (s.length()==0)) {
          s = "GRMN";
        }

        if (!_public) {
          s = DEFAULT_SETTINGS;
        }

        // s = "^DJI;^IXIC;BTC-USD;GRMN";
        parseSettings(s);
       } catch(ex) {
        debug("getSettings error: "+ex.getErrorMessage());
        parseSettings("GRMN");
      }
    }

    function parseSettings(s) {
      // count settings
      var n = 0;
      var m = s.length();
      for (var i=0; i<m; i++) {
        var ss = s.substring(i, i+1);
        if (ss.equals(";")) {
          n++;
        }
      }
     
      mSymbol    = new[n+1];
      mQuote     = new[n+1];
      mPrevQuote = new[n+1];
      mQuoteStr  = new[n+1];
      mChange    = new[n+1];
      mChangeStr = new[n+1];
      mUpdateT   = new[n+1];

      n = 0;
      m = s.length();
      var ss="";
      for (var i=0; i<m; i++) {
        if (s.substring(i, i+1).equals(";")) {
          mSymbol[n] = ss;
          n++;
          ss = "";
        } else {
          ss = ss + s.substring(i, i+1);
        }
      }


      if (ss.length()>0) {
        mSymbol[n] = ss;
      }

      for (var i=0; i<mSymbol.size(); i++) {
        debug(i+" "+mSymbol[i]);
      }
    }

    function onSettingsChanged() {
      getSettings();
    }

    /******************************************************************
     * HELPERS 
     ******************************************************************/  
    function debug (s) {
      try {
        if (_debug) {
          System.println("StockQuoteApp: "+s);
        } 
        if (s.find(" error:")!=null) {
          if (_sound) {
            Attention.playTone(Attention.TONE_ERROR);
          }
          if (!_debug) {
            System.println("=== ERROR =================================================================");
            var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
            var v = now.hour.format("%02d")+":"+now.min.format("%02d")+":"+now.sec.format("%02d");
            System.println(v);
            System.println(""+s);
            System.println("CombiSpeedView: "+s);
            System.println("===========================================================================");
          }
        }
      } catch (ex) {
        System.println("debug error:"+ex.getErrorMessage());
      }
    }

    function trim (s) {
      var l = s.length();
      var n = l;
      var m = 0;
      var stop;

      stop = false;
      for (var i=0; i<l; i+=1) {
        if (!stop) {
          if (s.substring(i, i+1).equals(" ")) {
            m = i+1;
          } else {
            stop = true;
          }
        }
      }

      stop = false;
      for (var i=l-1; i>0; i-=1) {
        if (!stop) {
          if (s.substring(i, i+1).equals(" ")) {
            n = i;
          } else {
            stop = true;
          }
        }
      }  

      if (n>m) {
        return s.substring(m, n);  
      } else {
        return "";
      }
    }

    function stringReplace(str, oldString, newString) {
      var result = str;

      while (true) {
        var index = result.find(oldString);

        if (index != null) {
          var index2 = index+oldString.length();
          result = result.substring(0, index) + newString + result.substring(index2, result.length());
        }
        else {
          return result;
        }
      }

      return null;
    }

    function modulo (v, m) {
      var r = v - Math.floor(v / m) * m;

      return r;
    }

    /******************************************************************
     * COMMUNICATION 
     ******************************************************************/  
    function killComm () {
      debug("KillComm");
      try {
        Communications.cancelAllRequests();
      } finally {
        mLoading = false;
        mLoadingCount = 0;
      }
    }

    function receiveKoers(responseCode, data) {
      try {
        debug("->  Data received with code "+responseCode.toString());  
        //debug("->  Data "+data);  


        if (
             (responseCode==200) && 
             (data["optionChain"] != null)  && 
             (data["optionChain"]["result"] !=null) &&
             (data["optionChain"]["result"][0] !=null) &&
             (data["optionChain"]["result"][0]["quote"] !=null) &&
             (data["optionChain"]["result"][0]["quote"]["regularMarketChange"] !=null) 
           )  
        {  
          var k  = data["optionChain"]["result"][0]["quote"]["regularMarketPrice"].toFloat();
          var c  = data["optionChain"]["result"][0]["quote"]["regularMarketChange"].toFloat();

          if (k>0) {
            mPrevQuote[mLoadSymbol] = mQuote[mLoadSymbol];
            mQuote[mLoadSymbol] = k;
            mChange[mLoadSymbol] = c;
            c = Math.round((c / k) * 1000)/10;

            if (k<1000) {
              if (k<100) {
                k = Math.round((k) * 1000)/1000;
                mQuoteStr[mLoadSymbol] = k.format("%.3f");
              } else {
                if (k<100) {
                  k = Math.round((k) * 100)/100;
                  mQuoteStr[mLoadSymbol]  = k.format("%.2f");
                } else {
                  k = Math.round((k) * 10)/10;
                  mQuoteStr[mLoadSymbol]  = k.format("%.1f");    
                }
              }
            } else {
              k = Math.round(k);
              var t1 = Math.floor(k/1000);
              var t2 = Math.round(k-t1*1000);
              mQuoteStr[mLoadSymbol] = t1.format("%i")+","+t2.format("%03d");
            }
            
            var t = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            mUpdateT[mLoadSymbol]    = t.day*24*3600+t.hour*3600*24+t.min*60+t.sec;
            mChangeStr[mLoadSymbol]  = c;
            mChangeStr[mLoadSymbol] = c.format("%.1f")+"%";
            if (c>0) {
              mChangeStr[mLoadSymbol] = "+"+mChangeStr[mLoadSymbol];
            }
          }
        } else {
          if (responseCode<0) {
            killComm();
          }
        }
        data = null;
        mLoading = false;
        mLoadingCount = 0;
  
      } catch (ex) {
         mLoading = false;
         mLoadingCount = 0;
         mQuoteStr[mLoadSymbol] = null;
         debug("receiveKoers error:"+ex.getErrorMessage());
      }
    }

    function getKoers(index) {
      try {
        if (mLoading) {
          debug("getKoers: loading");
          return;
        }
        if ((!mConnectie) || (1==0)) {
          debug("getKoers: Geen connectie");
          return;
        } 
  
        var i = index.toNumber();
        debug("getKoers index: "+i);   
        var symbol = mSymbol[i];
        debug("getKoers symbol: "+symbol); 
        if ((symbol==null) || (symbol.length()==0)) {
          mLoading = false;
          return;
        } 

        mLoading = true;
        mLoadingCount = 0;
        mLoadSymbol = i;

        Comm.makeWebRequest(
              "https://query2.finance.yahoo.com/v6/finance/options/"+symbol,
              {
                  
              },
              {
                  "Content-Type" => Comm.REQUEST_CONTENT_TYPE_URL_ENCODED
              },
              method(:receiveKoers)
          );
      } catch (ex) {
         mLoading = false;
         mLoadingCount = 0;
         debug("getKoers error: "+ex.getErrorMessage());
      }
    }

    /******************************************************************
     * DRAW HELPERS 
     ******************************************************************/  
    function setStdColor (dc) {
      if (getBackgroundColor() == Gfx.COLOR_BLACK) {
         dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
      } else {
          dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
      }   
    }

    /******************************************************************
     * VALUES 
     ******************************************************************/  
    hidden var mCounter = 0;

    function drawQuote(dc, x, y, index) {
      try {
        dc.setPenWidth(1);
        var h = dc.getTextDimensions("X", Gfx.FONT_SYSTEM_NUMBER_MEDIUM);

        var pq   = mPrevQuote[index];
        var q    = mQuote[index];
        var m    = mSymbol[index];
        var c    = mChange[index];
        var qStr = mQuoteStr[index];
        var cStr = mChangeStr[index];
        var t    = mUpdateT[index];
        var nt = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var f1 = 1.9;
        var f2 = 2.0;
        var f3 = 2.0;
        nt  = nt.day*24*3600+nt.hour*3600*24+nt.min*60+nt.sec;  

        if ((m==null) || (m.length()==0)) {
          m = "";
          qStr = null;
        }

        if (pq==null) {
          pq=q;
        }

        if (mSH<330) {
          f1 = 1.3;
          f2 = 4;
          f3 = 0;
        }

        if ((qStr==null) || (c==null) || (cStr==null)) {
          qStr = "...";
          if (m.length()==0) {
            qStr = "";
          }
          cStr = "";
          c = 0;
          t = -1;
        }



        setStdColor(dc);
        // titel
        dc.drawText(x, y+YMARGING-f1*h[0], Gfx.FONT_GLANCE, m, Gfx.TEXT_JUSTIFY_CENTER);

        if (mConnectie) {
          // Quote
          if (nt-t<=1) {
            if (q-pq<0) {
              dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
            }
            if (q-pq>0) {
              dc.setColor(Gfx.COLOR_DK_GREEN, Gfx.COLOR_TRANSPARENT);
            } 
            if (q-pq==0) {
              dc.setColor(Gfx.COLOR_DK_BLUE, Gfx.COLOR_TRANSPARENT);
            }              
          }
          dc.drawText(x, y-h[1]/f2, Gfx.FONT_SYSTEM_NUMBER_MEDIUM, qStr, Gfx.TEXT_JUSTIFY_CENTER);
     
          if (f3>0) {
            // change
            if (c<0) {
              dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
            }
            if (c>0) {
              dc.setColor(Gfx.COLOR_DK_GREEN, Gfx.COLOR_TRANSPARENT);
            }
            dc.drawText(x, y+h[1]/f3, Gfx.FONT_SYSTEM_MEDIUM, cStr, Gfx.TEXT_JUSTIFY_CENTER);
          }
        } else {
          dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
          dc.drawText(x, y, Gfx.FONT_SYSTEM_TINY, "NO CONN.", Gfx.TEXT_JUSTIFY_CENTER);   
        }
          
      } catch (ex) {
        debug("drawValues error: "+ex.getErrorMessage());
      }
    }

    function drawArrows (dc) {
      var m = mSymbol.size();

      if (mSH<330) {
        return;
      }

      if (mShowQuotes<m) {
        dc.setPenWidth(1);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);

        var w = 15;
        var h = 15;

        var wf = w/2;
        var hf = h/3;

        var x = 5;
        var y = 5;

        // Pijl naar links
        dc.drawLine (x    , y+h/2    , x+wf , y        );  
        dc.drawLine (x+wf , y        , x+wf , y+hf    );
        dc.drawLine (x+wf , y+hf     , x+w  , y+(hf)  );
        dc.drawLine (x+w  , y+(hf)   , x+w  , y+2*(hf));
        dc.drawLine (x+w  , y+2*(hf) , x+wf , y+2*(hf));
        dc.drawLine (x+wf , y+2*(hf) , x+wf , y+h      );
        dc.drawLine (x+wf , y+h      , x    , y+h/2    );

        // pijl naar rechts
        x = mW - w - w/3;
        y = mH - h - h/3;

        dc.drawLine (x+w     , y+h/2    , x+w-wf , y        );  
        dc.drawLine ( x+w-wf , y       ,x+w-wf , y+hf    );
        dc.drawLine (x , y+hf     , x+w-wf  , y+(hf)  );
        dc.drawLine (x , y+(hf)   , x       , y+2*(hf));
        dc.drawLine (x+w-wf  , y+2*(hf)     , x , y+2*(hf));
        dc.drawLine (x+w-wf  , y+2*(hf), x+w-wf   , y+h     );
        dc.drawLine (x+w  , y+h/2      , x+w-wf    , y+h    );

        // mid box
        //dc.drawLine(mW/2-50, mH/2-50, mW/2-50, mH/2+50);
        //dc.drawLine(mW/2-50, mH/2+50, mW/2+50, mH/2+50);
        //dc.drawLine(mW/2+50, mH/2+50, mW/2+50, mH/2-50);
        //dc.drawLine(mW/2+50, mH/2-50, mW/2-50, mH/2-50);
      }
    }

    function drawRefresh (dc) {
      if (mSH<330) {
        return;
      }

      if ((mLoading) || (mQueuIndex>0)) {
      } else {
        dc.setPenWidth(1);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        var r = 5;

        dc.drawCircle(r + r/1.5, mH -r - r/1.5, r);
      }
    }
    
    function drawLoading(dc) {
      if ((mLoading) || (mQueuIndex>0)) {
        mCounter++;
        var i = modulo(mCounter, 3);

        for (var j=0; j<3; j++) {
          dc.setPenWidth(4);
          dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
          if (i==j) {
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
          }
          dc.drawCircle(10+j*12, mH-10, 2);
        }

      }
    }

    function numFields (dc) {
      var col;
      var row;
      var h = dc.getTextDimensions("99,999", Gfx.FONT_SYSTEM_NUMBER_MEDIUM);

        //col = Math.round(mW / 239.0);
        //row = Math.round(mH / 158.0);

        col = Math.round(mW / h[0]);
        row = Math.round(mH / (h[1]*1.5));


      return col*row;
    }

    function currentIndex () {
       var m = mQuote.size();
       return modulo(mCurrentSymbol + mOffset, m).toNumber();
    }

    function drawValues (dc) {
      try {
        var x = mW/2;
        var y = mH/2;
        var col = 1;
        var row = 1;
        mShowQuotes = 1;
        var m = mQuote.size();
        var index = currentIndex () ;

        var h = dc.getTextDimensions("99,999", Gfx.FONT_SYSTEM_NUMBER_MEDIUM);

        //col = Math.round(mW / 239.0);
        //row = Math.round(mH / 158.0);

        col = Math.round(mW / h[0]);
        row = Math.round(mH / (h[1]*1.9));


        for (var j=0; j<row; j++) {
          for (var i=0; i<col; i++) {
            if (col==1) {
              x = mW/2;
            }
            if (col==2) {
              x = (mW/4) * (i*2+1);
            }

            if (row==1) {
              y = mH/2;
            }
            if (row==2) {
              y = (mH/4) * (j*2+1);
            }
            if (row==3) {
              y = (mH/2) * (j+0.5)+YMARGING;
            }
            if (row==4) {
              y = (mH/4) * (j+0.5);
            }
            if (row==5) {
              y = (mH/5) * (j+0.5);
            }

            if (index>=m) {
              index = 0;
            }
            drawQuote(dc, x, y, index);
            index++;
          }
        }
        mShowQuotes = col * row;
        
      } catch (ex) {
        debug("drawValues error "+ex.getErrorMessage());
      }
    }

    /******************************************************************
     * TIMERS 
     ******************************************************************/  
    function getAllQuotes() {
      pushQueue(-1); // wait
      pushQueue(-2); // wait
      pushQueue(-3); // wait
      var n = mSymbol.size();
      for (var i=0; i<n; i++) {
        pushQueue(i);
      }
    }
   
    function getDisplayedQuotes() {
      if (mFields==1) {
        var index = currentIndex();
        var m = mQuote.size();
        for (var i=0; i<mShowQuotes; i++) {
          if (index>=m) {
            index = 0;
          }
          pushQueue(index);
          pushQueue(-(index+1)); // pauze
          index++;
        } 
      } else {
        getAllQuotes();
      }  
    }

    function everyMinute() {
      var time = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
      debug("EveryMinute "+time.min+" ====================================================");

      // getDisplayedQuotes();
    }

    function every5Minutes() {
      var time = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
      debug("EveryMinute "+time.min+" ====================================================");

      getDisplayedQuotes();
    }

    function every15Minutes() {
      var time = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
      debug("EveryMinute "+time.min+" ====================================================");

      getDisplayedQuotes();
    }

    function execTimer() {
      try {
        var time = Gregorian.info(Time.now(), Time.FORMAT_SHORT);

        if (mLoading) {
          mLoadingCount++;
          if (mLoadingCount>25) {
            killComm();
          }
        }

        if (mLastMinute!=time.min) {
           debug("execTimer: "+time.min);
           try {
             everyMinute();
          
             if (!_public) {
               if ((mLastMinute==0) || ((time.min - Math.floor(time.min/5) * 5)==0))  {
                every5Minutes();
               }
             }

             if (_public) {
               if ((mLastMinute==0) || ((time.min - Math.floor(time.min/15) * 15)==0))  {
                every15Minutes();
               }
             }

           } finally {
             mLastMinute = time.min;
           }
        }
      } catch (ex) {
         debug("execTimer error: "+ex.getErrorMessage());
      }
    }

    /******************************************************************
     * Queue
     ******************************************************************/  
    var mQueuIndex = 0;
    var mQueue = new[40];
    var mQueuePause = false;

    function pushQueue(s) {
      var skip = false;

      // ontdubbel
      var n = mQueue.size();
      for (var i=0; i<n; i++) {
        var ss = mQueue[i];
        if ((ss!=null) && (ss.equals(s))) {
          skip = true;
        }
      }
    
      // toevoegen
      if (!skip) {
        n = mQueue.size();
        if (mQueuIndex<n) {
          //debug("push index "+mQueuIndex+", size: "+n);
          mQueue [mQueuIndex] = s;
          mQueuIndex++;
        } else {
          //debug("Queue overflow: "+s);
        }
      } else {
        debug("Queue already in queu: "+s);      
      }
    }

    function popQueue() {
      if (mQueuePause) {
        return null;
      }

      var result = mQueue[0];

      if (result!=null) {
        if (mQueuIndex>0) {
          mQueuIndex--;
        }
        var m = mQueue.size();
        for (var i=1; i<m; i++) {
          mQueue[i-1] = mQueue[i];
        }
        mQueue[m-1] = null;
      }

      return result;
    }

    function handleQueu () {
      if (mLoading) {
        return;
      }

      if (!mConnectie) {
        return;
      }

      var q = popQueue();
      if (q!=null) {
        if (q>=0) {
          getKoers(q);
        }
      }
    }

    /******************************************************************
     * COMPUTE 
     ******************************************************************/  
    function compute(info) {

      try {  
        mConnectie = System.getDeviceSettings().phoneConnected;
        mOffset = 0;
        mFields = 0;
        mSH = System.getDeviceSettings().screenHeight;
        mSW = System.getDeviceSettings().screenWidth;
      } catch (ex) {
          debug("Compute error: "+ex.getErrorMessage());
      }                  
    }

    /******************************************************************
     * On Update
     ******************************************************************/  
    function handleTouch() {
      try {
        if (GlobalTouched>=0) {
         
          // mShowQuotes
          if (GlobalTouched==0) {
            // alleen refresh
          } 

          if (GlobalTouched==1) {
            mCurrentSymbol --;
          } 

          if (GlobalTouched==2) {
            mCurrentSymbol ++;
          } 

          var n = mSymbol.size();

          if (mCurrentSymbol<0) {
            mCurrentSymbol = n-1;
          }

          if (mCurrentSymbol>=mSymbol.size()) {
            mCurrentSymbol = 0;
          }

          GlobalTouched = -1;
          getDisplayedQuotes();
        } 
      } catch (ex) {
        GlobalTouched = -1;
        debug("handleTouch error: "+ex.getErrorMessage());
      }
    }

    function onUpdate(dc) { 
      try {  
        mW = dc.getWidth();
        mH = dc.getHeight();
        dc.setColor(getBackgroundColor(), getBackgroundColor());
        dc.clear();
        if (mFirstShow) {
          getAllQuotes();
          mFirstShow = false;
        }
        setStdColor(dc);
        handleTouch();
        handleQueu();
        execTimer();
        try { 
          drawValues(dc);

          drawArrows(dc);
          drawRefresh (dc); 
          drawLoading(dc);
        } catch (ex) {
          debug("onUpdate draw error: "+ex.getErrorMessage());
        }   
         
        mOffset += numFields(dc);
        mFields++;
       
      } catch (ex) {
        debug("onUpdate ALL error: "+ex.getErrorMessage());
     }
    }

}
