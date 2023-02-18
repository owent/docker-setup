# nextcloue setup

1. Set environment `ADMIN_USENAME`, `ADMIN_TOKEN`, `NEXTCLOUD_DATA_DIR`, `NEXTCLOUD_APPS_DIR`, `NEXTCLOUD_ETC_DIR`
  > `mkdir -p $NEXTCLOUD_DATA_DIR $NEXTCLOUD_APPS_DIR $NEXTCLOUD_ETC_DIR && chmod 770 $NEXTCLOUD_DATA_DIR $NEXTCLOUD_APPS_DIR $NEXTCLOUD_ETC_DIR`
2. Use the final domain (e.g. `home.x-ha.com`) to setup nextcloud
3. Modify `trusted_domains` in `config.php` and add all trusted address
4. Modify `overwrite.cli.url` in `config.php` to set it to final homeurl of nextcloud.
5. Modify/Add `'default_phone_region' => 'CN',` in `config.php`
6. Set and mount nginx paths:
  + Set root of `nextcloud-fpm.nginx.conf` to `/usr/share/nginx/html/nextcloud`
  + Mount `$NEXTCLOUD_REVERSE_ROOT_DIR/nextcloud` -> `/usr/share/nginx/html/nextcloud`.
  + Mount `$NEXTCLOUD_APPS_DIR` -> `/usr/share/nginx/html/nextcloud/custom_apps`.

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
