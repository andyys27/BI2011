var status     = msg['status'];
var comp       = msg['compartment'];
var cardUid    = msg['uid'];
var stockA     = msg['stockA'].toString();
var stockB     = msg['stockB'].toString();

var dateStr = DateUtil.getCurrentDate("yyyyMMddHHmmss");

tmp['MSH']['MSH.3']['MSH.3.1'] = "ESP32_DISPENSER"; 
tmp['MSH']['MSH.7']['MSH.7.1'] = dateStr;           

tmp['ZMED']['ZMED.1']['ZMED.1.1'] = status;   
tmp['ZMED']['ZMED.2']['ZMED.2.1'] = comp;     
tmp['ZMED']['ZMED.3']['ZMED.3.1'] = cardUid;  
tmp['ZMED']['ZMED.4']['ZMED.4.1'] = stockA;   
tmp['ZMED']['ZMED.5']['ZMED.5.1'] = stockB;