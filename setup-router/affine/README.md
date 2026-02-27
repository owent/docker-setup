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

+ ~~查看功能ID和限制: `select id, feature, configs from features;`~~（新版配额已硬编码在程序中，修改该表无效）

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

+ 插入权限Flag（**新版SQL，无需 feature_id，触发器自动填充**）:
  > + reason 可以随便写，记录变更描述
  > + `type=1` 为配额类权限(quota)，`type=0` 为普通feature
  > + 切换到 lifetime_pro_plan_v1（先停用旧配额再添加新配额）：
  >  + `UPDATE user_features SET activated = false WHERE user_id = 'd5bdf98f-af29-4ccd-bd55-d643e803891f' AND type = 1 AND activated = true;`
  >  + `INSERT INTO user_features (user_id, name, type, activated, reason) VALUES ('d5bdf98f-af29-4ccd-bd55-d643e803891f', 'lifetime_pro_plan_v1', 1, true, 'sql');`
  > + 开启无限 Copilot AI：
  >  + `INSERT INTO user_features (user_id, name, type, activated, reason) VALUES ('d5bdf98f-af29-4ccd-bd55-d643e803891f', 'unlimited_copilot', 0, true, 'sql');`
  > + 开启 unlimited_workspace（跳过存储配额检查）：
  >  + `INSERT INTO user_features (user_id, name, type, activated, reason) VALUES ('d5bdf98f-af29-4ccd-bd55-d643e803891f', 'unlimited_workspace', 0, true, 'sql');`

> **注意（新版变更 2025-12）**：
> - `features` 表仍存在供向后兼容，但配额配置（blobLimit/storageQuota/memberLimit等）已**硬编码在应用程序源码**中
> - ~~修改 `features.configs`~~ **不再有效**，新版代码不再从数据库读取配额配置
> - 配额计划定义见：<https://github.com/toeverything/affine/blob/main/packages/backend/server/src/models/common/feature.ts>
> - Self-hosted 实例中 `free_plan_v1` 被当作 Pro 处理（100GB存储，10成员）
> - 工作区超过10席位需要 Team License，无法通过SQL绕过
