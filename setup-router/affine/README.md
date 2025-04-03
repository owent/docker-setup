# affine self host setup

## 设置

1. Setup container networks. ([../docker-network](../docker-network))
2. Set environment in `.env`
3. Initialize DB users: `affinedb` and DB: `affine_data`

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
> id |       feature        |                                                                             configs                                                                             
>----+----------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------
>  1 | copilot              | {}
>  2 | early_access         | {"whitelist":["@toeverything.info"]}
>  3 | early_access         | {"whitelist":[]}
>  4 | unlimited_workspace  | {}
>  5 | unlimited_copilot    | {}
>  6 | ai_early_access      | {}
>  7 | administrator        | {}
>  8 | free_plan_v1         | {"name":"Free","blobLimit":10485760,"storageQuota":10737418240,"historyPeriod":604800000,"memberLimit":3}
>  9 | pro_plan_v1          | {"name":"Pro","blobLimit":104857600,"storageQuota":107374182400,"historyPeriod":2592000000,"memberLimit":10}
> 10 | restricted_plan_v1   | {"name":"Restricted","blobLimit":1048576,"storageQuota":10485760,"historyPeriod":2592000000,"memberLimit":10}
> 11 | free_plan_v1         | {"name":"Free","blobLimit":104857600,"storageQuota":10737418240,"historyPeriod":604800000,"memberLimit":3}
> 12 | free_plan_v1         | {"name":"Free","blobLimit":10485760,"businessBlobLimit":104857600,"storageQuota":10737418240,"historyPeriod":604800000,"memberLimit":3}
> 13 | free_plan_v1         | {"name":"Free","blobLimit":10485760,"businessBlobLimit":104857600,"storageQuota":10737418240,"historyPeriod":604800000,"memberLimit":3,"copilotActionLimit":10}
> 14 | pro_plan_v1          | {"name":"Pro","blobLimit":104857600,"storageQuota":107374182400,"historyPeriod":2592000000,"memberLimit":10,"copilotActionLimit":10}
> 15 | restricted_plan_v1   | {"name":"Restricted","blobLimit":1048576,"storageQuota":10485760,"historyPeriod":2592000000,"memberLimit":10,"copilotActionLimit":10}
> 16 | lifetime_pro_plan_v1 | {"name":"Lifetime Pro","blobLimit":104857600,"storageQuota":1099511627776,"historyPeriod":2592000000,"memberLimit":10,"copilotActionLimit":10}
>(16 rows)
>```

+ 查看用户ID和当前权限: `select * from user_features;`

>```bash
> id |               user_id                | feature_id |   reason   |         created_at         | expired_at | activated 
>----+--------------------------------------+------------+------------+----------------------------+------------+-----------
>  2 | 3eae2420-77a6-45b1-b2ec-d2be829752a8 |          7 | Admin user | 2024-09-11 09:19:02.565+00 |            | t
>  1 | 3eae2420-77a6-45b1-b2ec-d2be829752a8 |         16 | sign up    | 2024-09-11 09:19:02.556+00 |            | t
>```

+ 插入权限Flag: `insert into user_features (id,user_id,feature_id,reason,activated) values (3,'3eae2420-77a6-45b1-b2ec-d2be829752a8',4,'AI request unlimited','t');`
  > + reason这个项可以随便写，记录权限描述的项
  > + 依次插入4,5,16
+ 修改成员数: `update features set configs = '{"name":"Lifetime Pro","blobLimit":104857600,"storageQuota":1099511627776,"historyPeriod":2592000000,"memberLimit":1000,"copilotActionLimit":10}' where id = 16;`
