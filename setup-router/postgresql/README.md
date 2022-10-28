# PostgreSQL

## 初始化

```bash
psql -h localhost -U postgres

  CREATE USER <用户名> WITH PASSWORD '<密码>' CREATEDB;
  CREATE DATABASE <数据库名> TEMPLATE template0 ENCODING 'UTF8';
  ALTER DATABASE <数据库名> OWNER TO <用户名>;
  GRANT ALL PRIVILEGES ON DATABASE <数据库名> TO <用户名>;
  GRANT ALL PRIVILEGES ON SCHEMA public TO <用户名>;

  \q
```
