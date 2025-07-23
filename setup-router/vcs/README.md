# VCS设置

## p4d

<https://www.bilibili.com/opus/883231136496484360>

### 开启Unicode模式

```bash
p4d -r /data/performance/p4d/root -p ssl:p4.w-oa.com:8666 -J /data/archive/p4d/journal -L /data/archive/p4d/log -xi
```

### SSL

```bash
# 生成自签名证书
export P4SSLDIR=/path/ssl; p4d -Gc
# 使用已有证书
export P4SSLDIR=/path/ssl; p4d -Gf -y
```

### 超级管理员

```bash
P4CLIENT_PORT=ssl:p4.w-oa.com:8666

# 信任新部署的p4服务器
p4 -p $P4CLIENT_PORT trust -f -y
# 创建账户
p4 -p $P4CLIENT_PORT user -f admin
# 设置“admin”的密码
p4 -p $P4CLIENT_PORT -u admin passwd
# 登入
p4 -p $P4CLIENT_PORT -u admin login
# 第一个执行 p4 protect 的用户会获得“super”权限。
p4 -p $P4CLIENT_PORT -u admin protect
```

### 设置

```bash
P4CLIENT_PORT=ssl:p4.w-oa.com:8666

# 设置服务器ID
p4 -p $P4CLIENT_PORT -u admin serverid Perforce
# p4 -p $P4CLIENT_PORT -u admin configure set serverid=PerforceServer

# 开启Unicode模式
p4d -p $P4CLIENT_PORT -xi

# 禁止自动创建未注册用户
p4 -p $P4CLIENT_PORT -u admin configure set dm.user.noautocreate=2
# 设置服务器安全等级，要求每个用户都有密码（这也是后面LDAP接入的前提条件）
p4 -p $P4CLIENT_PORT -u admin configure set security=3


# LDAP
p4 -p $P4CLIENT_PORT -u admin ldap -i << EOF
Name:     LDAP_DEFAULT
Host:     192.168.xxx.xxx
Port:     389 # 389 fornone, 636 for tls
Encryption:    none # tls/none
BindMethod:    search # search/simple
SearchBindDN:  uid=ldap-bind,ou=people,dc=w-oa,dc=com
SearchPasswd:  password
SimplePattern: uid=%user%,ou=people,dc=w-oa,dc=com
SearchBaseDN:  ou=people,dc=w-oa,dc=com
SearchFilter:  (&(objectClass=person)(memberof=cn=p4,ou=groups,dc=w-oa,dc=com)(uid=%user%))
SearchScope:    subtree
Options: downcase getattrs norealminusername
AttributeUid: uid
AttributeName: uid
AttributeEmail: mail
EOF

# 不验证证书(0: 不使用SSL, 1: 使用SSL并验证证书, 2: 使用SSL并信任证书)
p4 -p $P4CLIENT_PORT -u admin configure set auth.ldap.ssllevel=2

# 自动创建用户
p4 -p $P4CLIENT_PORT -u admin configure set auth.ldap.userautocreate=1
# 设置认证顺序
p4 -p $P4CLIENT_PORT -u admin configure set auth.default.method=ldap
p4 -p $P4CLIENT_PORT -u admin configure set auth.ldap.order.1=LDAP_DEFAULT
# 设置CA
# p4 configure set auth.ldap.cafile=perforce

# 自动同步用户和组
p4 -p $P4CLIENT_PORT -u admin configure set "startup.1=ldapsync -u -c -U -d -i 43200"
p4 -p $P4CLIENT_PORT -u admin configure set "startup.2=ldapsync -g -i 43200"

# 手动执行账户和组同步
p4 -p $P4CLIENT_PORT -u admin ldapsync -u -c -U -d
p4 -p $P4CLIENT_PORT -u admin ldapsync -g

# 开启Monitor
p4 -p $P4CLIENT_PORT -u admin configure set monitor=1
```

### 使用S3/Minio存储Archive

```bash
# 创建ArchiveDepot
p4 depot -t archive s3ArchiveDepotName
# 修改Depot的Address属性，设置 url,region,bucket,accessKey,secretKey,token
# Address: s3,region:us-east-1,bucket:p4d-depot,accessKey:,secretKey:******

# S3 Address
## AWS: Address: s3,region:us-west-2,bucket:my-archivebucket,accessKey:******,secretKey:******
## Digital Ocean: Address: s3,url:https://my-archivebucket.sfo3.digitaloceanspaces.com,bucket:my-archivebucket,accessKey:******,secretKey:******
## Minio: Address: s3,url:https://server:port/my-archivebucket,bucket:my-archivebucket,accessKey:******,secretKey:******
## GCP: Address: s3,url:https://storage.googleapis.com/my-archivebucket,bucket:my-archivebucket,accessKey:******,secretKey:******
```
