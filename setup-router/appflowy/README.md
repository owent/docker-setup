# appflowy setup

## Settings

1. Setup container networks. ([../docker-network](../docker-network))
2. Set environment in `.env`

## postgresql

Hint: `podman exec -it postgresql bash`

```bash
psql -h localhost -U postgres

  CREATE USER appflowydb WITH PASSWORD '<密码>' CREATEDB;
  CREATE USER supabase_auth_admin WITH PASSWORD '<密码>' CREATEDB;
  CREATE DATABASE appflowy_data TEMPLATE template0 ENCODING 'UTF8';
  ALTER DATABASE appflowy_data OWNER TO appflowydb;
  GRANT ALL PRIVILEGES ON DATABASE appflowy_data TO appflowydb;
  GRANT ALL PRIVILEGES ON SCHEMA public TO appflowydb;
  GRANT ALL PRIVILEGES ON DATABASE appflowy_data TO supabase_auth_admin;
  GRANT ALL PRIVILEGES ON SCHEMA public TO supabase_auth_admin;

  \q
```


## Documents

+ <https://github.com/AppFlowy-IO/AppFlowy-Cloud/blob/main/doc/DEPLOYMENT.md>
+ [Upgrade](https://github.com/AppFlowy-IO/AppFlowy-Cloud/blob/main/doc/DEPLOYMENT.md#6-upgrading-the-services)