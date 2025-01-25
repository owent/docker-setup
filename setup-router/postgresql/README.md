# PostgreSQL

## 初始化

```bash
podman exec -it postgresql psql -h localhost -d postgres -U postgres/或其他默认用户

  CREATE USER <用户名> WITH PASSWORD '<密码>' CREATEDB;
  CREATE DATABASE <数据库名> TEMPLATE template0 ENCODING 'UTF8';
  ALTER DATABASE <数据库名> OWNER TO <用户名>;
  GRANT ALL PRIVILEGES ON DATABASE <数据库名> TO <用户名>;
  GRANT ALL PRIVILEGES ON SCHEMA public TO <用户名>;

  \q
```

注意: 需要分配入站地址权限:

```bash
echo "host    all     all             10.0.0.0/16                 trust
host    all     all             172.23.1.10/16                 trust
host    all     all             172.22.1.10/16                 trust" >> /var/lib/postgresql/data/pgdata/pg_hba.conf

su postgres -- pg_ctl reload
```

## 备份数据库

```bash
podman run --rm -e "PGPASSWORD=password" --network=host postgres:latest
  pg_dump [db_name] -h [server] -U [username] -p $POSTGRESQL_PORT -f sqlbkp_`date +"%Y%m%d"`.bak

podman run --rm -e "PGPASSWORD=password" --network=host postgres:latest
  pg_dump nextcloud -h 127.0.0.1 -U nextcloud -p $POSTGRESQL_PORT -f nextcloud-sqlbkp_`date +"%Y%m%d"`.bak

podman run --rm -e "PGPASSWORD=password" --network=host --mount type=bind,source=$PWD,target=/data/postgres_backup postgres:latest
  pg_dump [db_name] -h [server] -U [username] -p $POSTGRESQL_PORT -f /data/postgres_backup/sqlbkp_`date +"%Y%m%d"`.bak
```

## 升级数据库

移动完数据库文件后可能需要

1. 使用 `REINDEX DATABASE <数据库名>;` 和 `ALTER DATABASE <数据库名> REFRESH COLLATION VERSION` 重建索引。
2. 修改配置文件允许内网地址连入: `/var/lib/postgresql/data/pgdata/pg_hba.conf` (本地路由地址: 172.23.1.10/16 和 docker地址: 10.0.2.100/16) 然后 `pg_ctl reload` 。

## 恢复数据库

```bash
podman run --rm --network=host --mount type=bind,source=$PWD,target=/data/postgres_backup postgres:latest \
  pg_restore -h localhost -p 5432 -U [username] -d [db_name] -v /data/postgres_backup/sqlbkp_*.bak

podman run --rm --network=host --mount type=bind,source=$PWD,target=/data/postgres_backup postgres:latest \
  psql -h localhost -p 5432 -U [username] --password [password] -d [db_name] -f /data/postgres_backup/sqlbkp_*.bak

podman run --rm --network=host --mount type=bind,source=$PWD,target=/data/postgres_backup postgres:latest \
  psql -h localhost -p 5432 -U postgres --no-password -d [db_name] -f /data/postgres_backup/sqlbkp_*.bak
```

管理员账号密码由启动时 `-e POSTGRES_PASSWORD=$ADMIN_TOKEN` 和 `-e POSTGRES_USER=$POSTGRESQL_ADMIN_USER` 指定。

