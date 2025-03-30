# appflowy setup

## Settings

1. Setup container networks. ([../docker-network](../docker-network))
2. Set environment in `.env`
3. Initialize DB users: `appflowydb`, `supabase_auth_admin` and DB: `appflowy_data`

## postgresql

Hint: `podman exec -it postgresql bash`

```bash
psql -h localhost -U postgres <<-EOSQL

  CREATE USER appflowydb WITH PASSWORD '<密码>' CREATEDB;
  ALTER USER appflowydb WITH CREATEROLE;
  CREATE DATABASE appflowy_data TEMPLATE template0 ENCODING 'UTF8';
  \c appflowy_data;
  ALTER DATABASE appflowy_data OWNER TO appflowydb;
  GRANT ALL PRIVILEGES ON DATABASE appflowy_data TO appflowydb;
  GRANT ALL PRIVILEGES ON SCHEMA public TO appflowydb;

  \q
EOSQL
```

Initialize: `supabase_auth_admin`

```bash
env POSTGRES_USER=owent POSTGRES_DB=appflowy_data SUPABASE_PASSWORD=$supabase_auth_admin_password \
  bash AppFlowy-Cloud/migrations/before/supabase_auth.sh

# Or sql below
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create the anon and authenticated roles if they don't exist
    CREATE OR REPLACE FUNCTION create_roles(roles text []) RETURNS void LANGUAGE plpgsql AS \$\$
    DECLARE role_name text;
    BEGIN FOREACH role_name IN ARRAY roles LOOP IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = role_name
    ) THEN EXECUTE 'CREATE ROLE ' || role_name;
    END IF;
    END LOOP;
    END;
    \$\$;

    -- Create supabase_auth_admin user if it does not exist
    DO \$\$ BEGIN IF NOT EXISTS (
        SELECT
        FROM pg_catalog.pg_roles
        WHERE rolname = 'supabase_auth_admin'
    ) THEN CREATE USER "supabase_auth_admin" BYPASSRLS NOINHERIT CREATEROLE LOGIN NOREPLICATION PASSWORD '$SUPABASE_PASSWORD';
    END IF;
    END \$\$;

    -- Create auth schema if it does not exist
    CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;

    -- Grant permissions
    GRANT CREATE ON DATABASE $POSTGRES_DB TO supabase_auth_admin;

    -- Set search_path for supabase_auth_admin
    ALTER USER supabase_auth_admin SET search_path = 'auth';
EOSQL
```

## Documents

+ <https://github.com/AppFlowy-IO/AppFlowy-Cloud/blob/main/doc/DEPLOYMENT.md>
+ [Upgrade](https://github.com/AppFlowy-IO/AppFlowy-Cloud/blob/main/doc/DEPLOYMENT.md#6-upgrading-the-services)

## FAQ

+ Shows `operator does not exist: uuid = text` or `no schema has been selected to create in` .

Option 1:

```bash
psql -U supabase_auth_admin -d appflowy_data <<-EOSQL
  ALTER ROLE supabase_auth_admin SET search_path TO auth,public;
  ALTER ROLE appflowydb SET search_path TO auth,public;
EOSQL
```

Option 2:

```bash
psql -U supabase_auth_admin -d appflowy_data <<-EOSQL
  insert into auth.schema_migrations values ('20221208132122');
EOSQL
```

+ Shows `error returned from database: permission denied for schema auth`

```bash
psql -U postgres -d appflowy_data <<-EOSQL
  ALTER SCHEMA auth OWNER TO appflowydb;
  GRANT ALL PRIVILEGES ON SCHEMA auth TO appflowydb;
  GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA auth TO appflowydb;
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA auth TO appflowydb;
  GRANT ALL PRIVILEGES ON ALL PROCEDURES IN SCHEMA auth TO appflowydb;
  GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA auth TO appflowydb;
  GRANT ALL PRIVILEGES ON SCHEMA auth TO supabase_auth_admin;
  GRANT ALL PRIVILEGES ON SCHEMA public TO supabase_auth_admin;
  GRANT ALL PRIVILEGES ON DATABASE appflowy_data TO supabase_auth_admin;
  GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA auth TO supabase_auth_admin;
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
  GRANT ALL PRIVILEGES ON ALL PROCEDURES IN SCHEMA auth TO supabase_auth_admin;
  GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;
EOSQL
```

+ Shows `error returned from database: must be owner of relation users`

```bash
psql -U supabase_auth_admin -d appflowy_data <<-EOSQL
  ALTER TABLE auth.users OWNER TO appflowydb;
EOSQL
```
