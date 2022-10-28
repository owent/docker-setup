# nextcloue setup

1. Set environment `ADMIN_USENAME`, `ADMIN_TOKEN`, `NEXTCLOUD_DATA_DIR`, `NEXTCLOUD_APPS_DIR`, `NEXTCLOUD_ETC_DIR`
  > `mkdir -p $NEXTCLOUD_DATA_DIR $NEXTCLOUD_APPS_DIR $NEXTCLOUD_ETC_DIR && chmod 770 $NEXTCLOUD_DATA_DIR $NEXTCLOUD_APPS_DIR $NEXTCLOUD_ETC_DIR`
2. Use the final domain (e.g. `home.x-ha.com`) to setup nextcloud
3. Modify `trusted_domains` in `config.php` and add all trusted address
4. Modify `overwrite.cli.url` in `config.php` to set it to final  homeurl of nextcloud.
5. Modify/Add `'default_phone_region' => 'CN',` in `config.php`

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
