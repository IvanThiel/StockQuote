using Toybox.Application as App;
using Toybox.WatchUi as Ui;

class StockQuoteApp extends App.AppBase {
     hidden var _mainView = null;

    function initialize() {
      AppBase.initialize();
    }

   function onSettingsChanged() { // triggered by settings change in GCM
      _mainView.getSettings();
      Ui.requestUpdate();   // update the view to reflect changes  
    }

    function getInitialView() {
      _mainView = new StockQuoteView();
      return [ _mainView , new StockQuoteBehaviourDelegate() ];
    }
  
}