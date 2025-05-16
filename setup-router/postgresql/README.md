# PostgreSQL

## 初始化

```bash
podman exec -it postgresql psql -h localhost -d postgres -U postgres/或其他默认用户

  CREATE USER <用户名> WITH PASSWORD '<密码>' CREATEDB;
  CREATE DATABASE <数据库名> TEMPLATE template0 ENCODING 'UTF8';
  # \c gitea;
  # CREATE EXTENSION vector;
  ALTER DATABASE <数据库名> OWNER TO <用户名>;
  GRANT ALL PRIVILEGES ON DATABASE <数据库名> TO <用户名>;
  GRANT ALL PRIVILEGES ON SCHEMA public TO <用户名>;

  \q
```

更多用户权限： `CREATE USER <用户名> WITH PASSWORD '<密码>' SUPERUSER CREATEDB CREATEROLE INHERIT LOGIN REPLICATION BYPASSRLS;`

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

# Remote mode(mount)
podman run --rm -e "PGPASSWORD=password" --network=host pg_dump [db_name] -h [server] -U [username] -p $POSTGRESQL_PORT -f /data/postgres_backup/sqlbkp_`date +"%Y%m%d"`.bak

# Remote mode(stdout)
podman run --rm -e "PGPASSWORD=password" --network=host pg_dump [db_name] -h [server] -U [username] -p $POSTGRESQL_PORT > sqlbkp_`date +"%Y%m%d"`.bak

# Remote mode(mount, data-only)
podman run --rm -e "PGPASSWORD=password" --network=host pg_dump --data-only [db_name] -h [server] -U [username] -p $POSTGRESQL_PORT -f /data/postgres_backup/sqlbkp_`date +"%Y%m%d"`.bak

# Remote mode(stdout, data-only)
podman run --rm -e "PGPASSWORD=password" --network=host pg_dump --data-only [db_name] -h [server] -U [username] -p $POSTGRESQL_PORT > sqlbkp_`date +"%Y%m%d"`.bak

# Local mode(stdout)
podman exec -it postgresql pg_dump -U [username] -d [db_name] > sqlbkp_`date +"%Y%m%d"`.bak

# Local mode(stdout, data-only)
podman exec -it postgresql pg_dump --data-only -U [username] -d [db_name] > sqlbkp_`date +"%Y%m%d"`.bak
```

## 升级数据库

移动完数据库文件后可能需要

1. 使用 `REINDEX DATABASE <数据库名>;` 和 `ALTER DATABASE <数据库名> REFRESH COLLATION VERSION` 重建索引。
2. 修改配置文件允许内网地址连入: `/var/lib/postgresql/data/pgdata/pg_hba.conf` (本地路由地址: 172.23.1.10/16 和 docker地址: 10.0.2.100/16) 然后 `pg_ctl reload` 。

## 恢复数据库

```bash
# Remote mode(mount)
podman run --rm --network=host --mount type=bind,source=$PWD,target=/data/postgres_backup postgres:latest \
  pg_restore -h localhost -p 5432 -U [username] -d [db_name] -v /data/postgres_backup/sqlbkp_*.bak

# Remote mode(mount)
podman run --rm --network=host --mount type=bind,source=$PWD,target=/data/postgres_backup postgres:latest \
  psql -h localhost -p 5432 -U [username] --password [password] -d [db_name] -f /data/postgres_backup/sqlbkp_*.bak

# Remote mode(mount)
podman run --rm --network=host --mount type=bind,source=$PWD,target=/data/postgres_backup postgres:latest \
  psql -h localhost -p 5432 -U postgres --no-password -d [db_name] -f /data/postgres_backup/sqlbkp_*.bak

# Local mode(mount)
cat sqlbkp_`date +"%Y%m%d"`.bak | podman exec -it postgresql psql -U [username] -d [db_name]

# Local mode(stdout, data-only)
cat sqlbkp_`date +"%Y%m%d"`.bak | podman exec -it postgresql psql -U [username] -d [db_name]
```

管理员账号密码由启动时 `-e POSTGRES_PASSWORD=$ADMIN_TOKEN` 和 `-e POSTGRES_USER=$POSTGRESQL_ADMIN_USER` 指定。

## 常用指令

+ 切换数据库: `\c <数据库名>`
+ 查看表结构: `\d <表名>` / `\d+ <表名>`
+ 查看用户权限: `\dn+`
+ 查看所有表(public): `SELECT * FROM information_schema.tables WHERE table_schema = 'public';`
+ 查看权限表: `SELECT * FROM pg_roles WHERE rolname = current_user;`
+ 查看Role表: `SELECT * FROM pg_catalog.pg_class WHERE relname = '<relation_name>';`
+ 更改所有者: `ALTER TABLE <relation_name> OWNER TO <new_owner>;`
+ 中数据库的所有Session: `SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '<database>';`

## 常见问题

+ 权限从属问题: `Only roles with the CREATEROLE attribute and the ADMIN option on role "<to_role>" may alter this role.`

```bash
psql -U <管理员用户> -d <数据库名> <<-EOSQL
  GRANT <from_role> TO <to_role> WITH ADMIN TRUE; 
EOSQL
```

+ 子用户权限错误: `ERROR:  must be able to SET ROLE "supabase_auth_admin"`

```bash
psql -U postgres -d appflowy_data <<-EOSQL
  GRANT supabase_auth_admin to postgres;
EOSQL
```
