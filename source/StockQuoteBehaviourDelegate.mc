using Toybox.WatchUi as Ui;

class StockQuoteBehaviourDelegate extends Ui.BehaviorDelegate {

    function initialize() {
      BehaviorDelegate.initialize();
    }

    function onTap(evt) {
      var xx = evt.getCoordinates()[0];
      var yy = evt.getCoordinates()[1];
      GlobalTouched = -1;

      if ((xx<75) && (yy<75)) { GlobalTouched = 1; } // links boven
      if ((xx>mW-75) && (yy>mH-75)) { GlobalTouched = 2; } // rechts onder 
      if ((xx>mW/2-50) && (yy>mH/2-50) && (xx<mW/2+50) && (yy<mH/2+50) ) { GlobalTouched = 0; } // midden
      if ((xx<75) && (yy>mH-75)) { GlobalTouched = 0; } // links onder
      if ((xx>mW-75) && (yy<75)) { GlobalTouched = 0; } // rechts boven

      if (GlobalTouched>=0) {  
        Ui.requestUpdate();
        return true;  
      } else {
        return false;
      }  
    }

}