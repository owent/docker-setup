# LLM集成

## MCP in LiteLLM gateway

<https://github.com/BerriAI/litellm/pull/9426>

## Azure OpenAI模型和可用区域

https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/models#standard-deployment-model-availability

## PostgreSQL 数据库初始化

注意: 需要分配入站地址权限:

```bash
echo "host    all     all             10.0.0.0/16                 trust
host    all     all             172.23.1.10/16                 trust
host    all     all             172.22.1.10/16                 trust" >> /var/lib/postgresql/data/pgdata/pg_hba.conf

su postgres -- pg_ctl reload
```

### For LiteLLM

```bash
podman exec -it postgresql psql -h localhost -d postgres -U postgres/或其他默认用户

  CREATE USER llm WITH PASSWORD '<密码>' CREATEDB;
  CREATE DATABASE litellm TEMPLATE template0 ENCODING 'UTF8';
  ALTER DATABASE litellm OWNER TO llm;
  GRANT ALL PRIVILEGES ON DATABASE litellm TO llm;
  GRANT ALL PRIVILEGES ON SCHEMA public TO llm;

ALTER DEFAULT PRIVILEGES GRANT ALL ON TABLES TO llm;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO llm;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO llm;

  \q
```

### For OpenWebUI

```bash
podman exec -it postgresql psql -h localhost -d postgres -U postgres/或其他默认用户

  CREATE USER llm WITH PASSWORD '<密码>' CREATEDB;
  CREATE DATABASE openwebui TEMPLATE template0 ENCODING 'UTF8';
  ALTER DATABASE openwebui OWNER TO llm;
  GRANT ALL PRIVILEGES ON DATABASE openwebui TO llm;
  GRANT ALL PRIVILEGES ON SCHEMA public TO llm;

  \q
```

### For Lobehub

清空远程模型设置缓存。

```bash
podman exec -it postgresql psql -h localhost -d postgres -U postgres/或其他默认用户

  DELETE FROM ai_models WHERE source = 'remote';
  DELETE FROM ai_models WHERE provider_id = 'openai' AND source = 'remote';
  DELETE FROM ai_models WHERE provider_id = 'aihubmix' AND source = 'remote';
  DELETE FROM ai_models WHERE provider_id = 'openrouter' AND source = 'remote';
  DELETE FROM ai_models WHERE source = 'remote' AND id in ('gpt-latest', 'gpt-latest', 'gpt-latest-mini', 'gpt-latest-nano', 'gpt-latest-pro', 'gpt-latest-image', 'gpt-latest-image-mini', 'gpt-latest-codex', 'gpt-latest-codex-mini', 'gpt-latest-codex-max');
```
