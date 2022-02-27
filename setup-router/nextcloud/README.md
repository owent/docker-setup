# nextcloue setup

1. Set environment `ADMIN_USENAME`, `ADMIN_TOKEN`, `NEXTCLOUD_DATA_DIR`
  > `mkdir -p $NEXTCLOUD_DATA_DIR && chmod 770 $NEXTCLOUD_DATA_DIR`
2. Use the final domain (e.g. `home-router.x-ha.com`) to setup nextcloud
3. Modify `trusted_domains` in `config.php` and add all trusted address
4. Modify `overwrite.cli.url` in `config.php` to set it to final  homeurl of nextcloud.
