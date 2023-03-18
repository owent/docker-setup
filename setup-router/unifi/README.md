# Unifi controller 配置

+ 请设置 Unifi controller/System/Advanced/Inform Host 到正确的宿主机IP，否则controller会检测自己的地址下发，会导致AP Adopting失败。
+ 改端口需要设置 `$UNIFI_CONTROLLER_ETC_DIR/data/system.properties` 。
  比如 `unifi.https.port=$UNIFI_CONTROLLER_WEB_PORT` 。
