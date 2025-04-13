# affine self host setup

## 设置

1. Setup container networks. ([../docker-network](../docker-network))
2. Set environment in `.env`
3. Initialize DB users: `affinedb` and DB: `affine_data`

## 导入配置

+ vim `~/affine/etc/config.schema.json`

```json
{
    "$schema": "https://github.com/toeverything/affine/releases/latest/download/config.schema.json",
    "copilot": {
      "enabled": true,
      "providers.openai": {
        "apiKey": "sk-xxxx",
        "baseURL": "<baseURL>"
      }
    }
}
```

+ Importing: `podman exec affine-server node --import ./scripts/register.js ./dist/data/index.js import-config /root/.affine/config/config.schema.json`
+ Restart server: `podman restart affine-server`

## postgresql

Hint: `podman exec -it postgresql bash`

```bash
psql -h localhost -U postgres <<-EOSQL

  CREATE USER affinedb WITH PASSWORD '<密码>' CREATEDB CREATEROLE;
  CREATE DATABASE affine_data TEMPLATE template0 ENCODING 'UTF8';
  \c affine_data;
  CREATE EXTENSION vector;
  ALTER DATABASE affine_data OWNER TO affinedb;
  GRANT ALL PRIVILEGES ON DATABASE affine_data TO affinedb;
  GRANT ALL PRIVILEGES ON SCHEMA public TO affinedb;

  \q
EOSQL
```

## 文档

+ Docker compose: <https://github.com/toeverything/affine/releases/latest/download/docker-compose.yml>
+ Docker and env: <https://github.com/toeverything/AFFiNE/tree/canary/.docker/selfhost>
+ [Upgrade](https://docs.affine.pro/docs/self-host-affine/affine-self-hosted-0.21-upgrade-guide)
+ Admin页面: `<domain>/admin/accounts`

## 定制化AI服务和权限

### AI代理设置

修改配置文件: `~/affine/etc/affine.js`

```ts
AFFiNE.use('copilot', {
  openai: {
    baseURL: 'https://API代理网址/v1',
    apiKey: '你的Key',
  },
  # 后面的fal api可以不管，如果你只需要对话功能
  # 末尾的括号解注释
})
```

### 用户权限

Hint: `podman exec -it postgresql psql -U affinedb`

+ 查看功能ID和限制: `select id, feature, configs from features;`
  
>```bash
>---
>| id  | feature                | version | type | configs                                                                                                                                                        | created_at                   | updated_at                   |
>| --- | ---------------------- | ------- | ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- | ---------------------------- |
>| 1   | "free_plan_v1"         | 4       | 1    | "{""name"":""Pro"",""blobLimit"":104857600,""storageQuota"":107374182400,""historyPeriod"":2592000000,""memberLimit"":10,""copilotActionLimit"":10}"           | "2025-04-04 00:32:44.872+08" | "2025-04-06 00:23:20.525+08" |
>| 2   | "pro_plan_v1"          | 2       | 1    | "{""name"":""Pro"",""blobLimit"":104857600,""storageQuota"":107374182400,""historyPeriod"":2592000000,""memberLimit"":10,""copilotActionLimit"":10}"           | "2025-04-04 00:32:44.876+08" | "2025-04-06 00:23:20.531+08" |
>| 3   | "lifetime_pro_plan_v1" | 1       | 1    | "{""name"":""Lifetime Pro"",""blobLimit"":104857600,""storageQuota"":1099511627776,""historyPeriod"":2592000000,""memberLimit"":10,""copilotActionLimit"":10}" | "2025-04-04 00:32:44.878+08" | "2025-04-06 00:23:20.536+08" |
>| 4   | "team_plan_v1"         | 1       | 1    | "{""name"":""Team Workspace"",""blobLimit"":524288000,""storageQuota"":107374182400,""historyPeriod"":2592000000,""memberLimit"":1,""seatQuota"":21474836480}" | "2025-04-04 00:32:44.882+08" | "2025-04-06 00:23:20.541+08" |
>| 5   | "early_access"         | 2       | 0    | "{""whitelist"":[]}"                                                                                                                                           | "2025-04-04 00:32:44.886+08" | "2025-04-06 00:23:20.546+08" |
>| 6   | "unlimited_workspace"  | 1       | 0    | "{}"                                                                                                                                                           | "2025-04-04 00:32:44.888+08" | "2025-04-06 00:23:20.549+08" |
>| 7   | "unlimited_copilot"    | 1       | 0    | "{}"                                                                                                                                                           | "2025-04-04 00:32:44.893+08" | "2025-04-06 00:23:20.553+08" |
>| 8   | "ai_early_access"      | 1       | 0    | "{}"                                                                                                                                                           | "2025-04-04 00:32:44.895+08" | "2025-04-06 00:23:20.556+08" |
>| 9   | "administrator"        | 1       | 0    | "{}"                                                                                                                                                           | "2025-04-04 00:32:44.897+08" | "2025-04-06 00:23:20.559+08" |
>(16 rows)
>```

+ 查看用户ID和当前权限: `select * from user_features;`

>```bash
> | "id" | "user_id"                              | "feature_id" | "reason          | "created_at"                 | "expired_at" | "activated"  | "name"              | "type" |
> | ---- | -------------------------------------- | ------------ | ---------------- | ---------------------------- | ------------ | ------------ | ------------------- | ------ |
> | 1    | "d5bdf98f-af29-4ccd-bd55-d643e803891f" | 1            | "signup"         | "2025-04-04 00:36:01.703+08" | [null]       | true         | "free_plan_v1"      | 1      |
> | 2    | "d5bdf98f-af29-4ccd-bd55-d643e803891f" | 9            | "selfhost setup" | "2025-04-04 00:36:01.703+08" | [null]       | true         | "administrator"     | 0      |
> | 3    | "d5bdf98f-af29-4ccd-bd55-d643e803891f" | 7            | "admin panel"    | "2025-04-04 00:38:37.624+08" | [null]       | true         | "unlimited_copilot" | 0      |
> | 4    | "3b0dba9a-0513-4935-8de1-70620ca65af7" | 1            | "signup"         | "2025-04-04 00:36:01.703+08" | [null]       | true         | "free_plan_v1"      | 1      |
> | 5    | "3b0dba9a-0513-4935-8de1-70620ca65af7" | 7            | "admin panel"    | "2025-04-04 00:59:50.002+08" | [null]       | true         | "unlimited_copilot" | 0      |
> | 6    | "3b0dba9a-0513-4935-8de1-70620ca65af7" | 9            | "admin panel"    | "2025-04-04 00:59:50.012+08" | [null]       | true         | "administrator"     | 0      |
>```

+ 插入权限Flag:
  > + reason这个项可以随便写，记录权限描述的项
  > + 依次插入3,6,7
  >  + `insert into user_features (id,user_id,feature_id,reason,activated,name,type) values (7,'d5bdf98f-af29-4ccd-bd55-d643e803891f',3,'sql','t', 'lifetime_pro_plan_v1', 1);`
  >  + `insert into user_features (id,user_id,feature_id,reason,activated,name,type) values (8,'d5bdf98f-af29-4ccd-bd55-d643e803891f',6,'sql','t', 'unlimited_workspace', 0);`
  >  + `insert into user_features (id,user_id,feature_id,reason,activated,name,type) values (9,'d5bdf98f-af29-4ccd-bd55-d643e803891f',7,'sql','t', 'unlimited_copilot', 0);`
  > + 删除free_plan_v1
  >  + `delete from user_features where id = 1;`
+ 修改成员数: `update features set configs = '{"name":"Lifetime Pro","blobLimit":104857600,"storageQuota":1099511627776,"historyPeriod":2592000000,"memberLimit":1000,"copilotActionLimit":10}' where id = 16;`
  + 如果无效，直接改Pro的授权限制
  + 每次更新会被重置，需要重新设置一下
