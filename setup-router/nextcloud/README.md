# nextcloue setup

1. Set environment `ADMIN_USENAME`, `ADMIN_TOKEN`, `NEXTCLOUD_DATA_DIR`, `NEXTCLOUD_APPS_DIR`, `NEXTCLOUD_ETC_DIR`

  > `mkdir -p $NEXTCLOUD_DATA_DIR $NEXTCLOUD_APPS_DIR $NEXTCLOUD_ETC_DIR && chmod 770 $NEXTCLOUD_DATA_DIR $NEXTCLOUD_APPS_DIR $NEXTCLOUD_ETC_DIR`

1. Use the final domain (e.g. `home.x-ha.com`) to setup nextcloud
1. Modify/Add settings in `config.php`
  >
  > ```php
  > $CONFIG = array(
  >  'trusted_domains' => array ( 0 => 'LOCAL_IP:LOCAL_PORT', ),
  >  'overwritehost' => 'home.x-ha.com:6443',
  >  'overwriteprotocol' => 'https',
  >  'trusted_proxies' => array ( 0 => '0.0.0.0/32', ),
  >  'overwrite.cli.url' => 'https://home.x-ha.com:6443',
  >  'default_phone_region' => 'CN',`
  >  'versions_retention_obligation' => 'auto, 30',
  >  'trashbin_retention_obligation' => 'auto, 180',
  > );
  > ```
  >
1. Set and mount nginx paths:
  >
  > + Set root of `nextcloud-fpm.nginx.conf` to `/usr/share/nginx/html/nextcloud`
  > + Mount `$NEXTCLOUD_REVERSE_ROOT_DIR/nextcloud` -> `/usr/share/nginx/html/nextcloud`.
  > + Mount `$NEXTCLOUD_APPS_DIR` -> `/usr/share/nginx/html/nextcloud/custom_apps`.
  >

## occ commands

```bash
podman exec -u <run user> <container name> env PHP_MEMORY_LIMIT=1024M php occ ...

# Examples
podman exec -u www-data nextcloud env PHP_MEMORY_LIMIT=1024M php occ app:install documentserver_community
```

## postgresql

```bash
psql -h localhost -U postgres

  CREATE USER nextcloud WITH PASSWORD '<密码>' CREATEDB;
  CREATE DATABASE nextcloud TEMPLATE template0 ENCODING 'UTF8';
  ALTER DATABASE nextcloud OWNER TO nextcloud;
  GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;
  GRANT ALL PRIVILEGES ON SCHEMA public TO nextcloud;

  \q
```

## 连接onlyoffice

注意: 如果局域网跨机器需要设置DNS，本地解析指向内网地址，外网解析走正常DNS/DDNS 。否则跨网点网络很不稳定。

## LDAP账户清理

```bash
sudo -E -u podman exec -u www-data nextcloud php occ ldap:show-remnants
sudo -E -u podman exec -u www-data nextcloud php occ user:delete USER_NAME
```
