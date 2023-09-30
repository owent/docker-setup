# PostgreSQL

## 初始化

```bash
podman exec -it postgresql psql -h localhost -U postgres/或其他默认用户

  CREATE USER <用户名> WITH PASSWORD '<密码>' CREATEDB;
  CREATE DATABASE <数据库名> TEMPLATE template0 ENCODING 'UTF8';
  ALTER DATABASE <数据库名> OWNER TO <用户名>;
  GRANT ALL PRIVILEGES ON DATABASE <数据库名> TO <用户名>;
  GRANT ALL PRIVILEGES ON SCHEMA public TO <用户名>;

  \q
```

## 备份数据库

```bash
podman run --rm -e "PGPASSWORD=password" docker.io/postgres:latest
  pg_dump [db_name] -h [server] -U [username] -p $POSTGRESQL_PORT -f sqlbkp_`date +"%Y%m%d"`.bak


podman run --rm -e "PGPASSWORD=password" docker.io/postgres:latest
  pg_dump nextcloud -h 127.0.0.1 -U nextcloud -p $POSTGRESQL_PORT -f nextcloud-sqlbkp_`date +"%Y%m%d"`.bak
```

## 升级数据库

移动完数据库文件后可能需要

1. 使用 `REINDEX DATABASE <数据库名>;` 和 `ALTER DATABASE <数据库名> REFRESH COLLATION VERSION` 重建索引。
2. 修改配置文件允许内网地址连入: `/var/lib/postgresql/data/pgdata/pg_hba.conf` (本地路由地址: 172.23.1.10/16 和 docker地址: 10.0.2.100/16) 然后 `pg_ctl reload` 。
