#!/system/bin/sh

/system/bin/dmesg -S | /system/bin/grep -e "FAULT in" -e "EXCH: trapType" -e "MTK: EXCEPTION in thread" -e TeeSeApi -e OMATA -e SE_TA -e TeeSeApi -e Nxp \
-e SN100 > /data/SecureElement/logData/log/kernellog
chmod 777 /data/SecureElement/logData/log/kernellog
/system/bin/logcat -d | /system/bin/grep -e "Disabling NFC" -e "Enabling NFC" -e SeRFHandler_receive -e NFCSwipeActivity -e "whole hci is" -e "SeHciReceiver" \
 -e eid-hal -e eSEPower -e SecureElement -e eSE-HAL -e VSES -e NxpNci -e data_trace > /data/SecureElement/logData/log/mainlog
chmod 777 /data/SecureElement/logData/log/mainlog

if [ -f /data/vendor/nfc/nci/nfc_event_2.txt  ]; then
  chmod 604 /data/vendor/nfc/nci/nfc_event_2.txt
  cp /data/vendor/nfc/nci/nfc_event_2.txt /data/SecureElement/logData/log/
  chmod 604 /data/SecureElement/logData/log/nfc_event_2.txt
  chmod 600 /data/vendor/nfc/nci/nfc_event_2.txt
else
  chmod 604 /data/vendor/nfc/nci/nfc_event.txt
  cp /data/vendor/nfc/nci/nfc_event.txt /data/SecureElement/logData/log/
  chmod 604 /data/SecureElement/logData/log/nfc_event.txt
  chmod 600 /data/vendor/nfc/nci/nfc_event.txt
fi
if [ -f /data/vendor/nfc/nci/nfc_nci_log_2.txt ]; then
  chmod 604 /data/vendor/nfc/nci/nfc_nci_log_2.txt
  cp /data/vendor/nfc/nci/nfc_nci_log_2.txt /data/SecureElement/logData/log/
  chmod 604 /data/SecureElement/logData/log/nfc_nci_log_2.txt
  chmod 600 /data/vendor/nfc/nci/nfc_nci_log_2.txt
else
  chmod 604 /data/vendor/nfc/nci/nfc_nci_log.txt
  cp /data/vendor/nfc/nci/nfc_nci_log.txt /data/SecureElement/logData/log/
  chmod 604 /data/SecureElement/logData/log/nfc_nci_log.txt
  chmod 600 /data/vendor/nfc/nci/nfc_nci_log.txt
fi
if [ -f /data/vendor/nfc/nci/nfc_log_2.txt ]; then
  chmod 604 /data/vendor/nfc/nci/nfc_log_2.txt
  cp /data/vendor/nfc/nci/nfc_log_2.txt /data/SecureElement/logData/log/
  chmod 604 /data/SecureElement/logData/log/nfc_log_2.txt
  chmod 600 /data/vendor/nfc/nci/nfc_log_2.txt
else
  chmod 604 /data/vendor/nfc/nci/nfc_log.txt
  cp /data/vendor/nfc/nci/nfc_log.txt /data/SecureElement/logData/log/
  chmod 604 /data/SecureElement/logData/log/nfc_log.txt
  chmod 600 /data/vendor/nfc/nci/nfc_log.txt
fi

setprop persist.vendor.vivo.catselog finish