# Authentik

LDAP属性文档: <https://docs.goauthentik.io/add-secure-apps/providers/ldap>

## LDAP for linux

**注意: Authentik在同时存在多个Provider和Base DN时，不允许一个Provider的Base DN是另一个的前缀。**

```bash
sudo apt install -y sssd-ldap libpam-sss libnss-sss libpam-mkhomedir
## RHEL like
## sudo dnf install -y sssd sssd-client sssd-ldap sssd-tools oddjob-mkhomedir

# 修改配置文件: /etc/sssd/conf.d/sssd.conf
echo "
[sssd]
services = nss, pam
domains = my-ldap-domain

[domain/my-ldap-domain]
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap

# 用户设置
default_shell = /bin/bash

ldap_uri = ldaps://ldap.yourcompany.com
ldap_search_base = dc=example,dc=com
ldap_user_search_filter = (&(objectClass=user)(|(memberOf=cn=admin,ou=groups,dc=example,dc=com)(memberOf=cn=cluster-*,ou=groups,dc=example,dc=com)(memberOf=cn=it-user,ou=groups,dc=example,dc=com)))
# ldap_group_search_filter =  (&(objectClass=group)(|(cn=ops-team)(cn=dev-team)))
# ldap_group_search_filter = (&(objectClass=group)(description=linux-access))
# 自定义属性一定要用驼峰命名，使用自定义属性posixGroupName作为组名，以减少组名长度,注意创建组的时候添加这个属性
ldap_group_search_filter = (&(objectClass=group)(posixLdapAuthGroup=*)(posixGroupName=*))

# 如果需要账号绑定
ldap_default_bind_dn = cn=admin,dc=example,dc=com
ldap_default_authtok = YOUR_PASSWORD

# -------------------------------------------
# 属性映射 (适配 Authentik)
# -------------------------------------------
# Authentik 默认使用 cn 作为用户名，uid 作为 UUID。
# 如果你想用 Authentik 的 Username 登录 Linux，通常映射如下：
ldap_schema = rfc2307bis
# 告诉 SSSD 用户对象是 'posixAccount', 如果不存在也可以试试 inetOrgPerson, person. 不能用 user ,sssd有硬编码，用user会导致找不到主组
ldap_user_object_class = posixAccount
# 告诉 SSSD 组对象是 'posixGroup', 其他可选名字是 group, groupOfNames, groupOfUniqueNames
ldap_group_object_class = posixGroup

# -------------------------------------------
# 属性映射 (Attribute Mapping)
# -------------------------------------------
# Authentik 的 name 属性通常对应登录名
ldap_user_name = cn
ldap_group_name = posixGroupName
ldap_group_member = member
ldap_user_uuid = uid
ldap_group_uuid = uid
ldap_user_uid_number = uidNumber
ldap_user_gid_number = gidNumber
ldap_group_gid_number = gidNumber

# --- ID 映射是 AD 专用的， Authentik并不支持，所以要关闭  ---
ldap_id_mapping = False
# 只接受这个范围内的 LDAP UID/GID，请注意不要和 /etc/subuid 与 /etc/subgid 冲突
# Applications -> Providers → LDAP Provider 设置用户ID和组ID要在这个范围内
min_id = 80000000
max_id = 99999999

# 禁用rootDSE查询，Authentik可能不提供
ldap_disable_referrals = true
# 不要求每个用户都有主组
auto_private_groups = hybrid
# 禁用 LDAP sudo，使用本地 sudoers 文件
sudo_provider = none

# 允许缓存凭证（断网也能登录）
cache_credentials = True
# 离线凭据过期时间(天)
offline_credentials_expiration = 30
# 即使在线，也缓存用户信息一段时间，降低拉取LDAP服务频率。(秒)
entry_cache_timeout = 7200

enumerate = False

# SSL/TLS 设置 (如果是自签名证书或测试环境，可以设为 allow 或 never)
ldap_tls_reqcert = allow
" | sudo tee /etc/sssd/conf.d/sssd.conf

sudo bash -c 'chmod 600 /etc/sssd/conf.d/*'
sudo bash -c 'chown root:root /etc/sssd/conf.d/*'

# LDAP 用户搜词启动自动创建Home目录
sudo pam-auth-update --enable mkhomedir
## RHEL like
## sudo systemctl enable --now oddjobd
## sudo authselect enable-feature with-mkhomedir
## sudo authselect apply-changes

# 允许 ldap-admins 组的成员执行所有 sudo 命令
echo "
%ldap-admins ALL=(ALL) ALL
" | sudo tee /etc/sudoers.d/ldap-admins

# 允许 ldap-users 组的成员执行扮演 tools
echo "
%ldap-users ALL=(tools) NOPASSWD: ALL
" | sudo tee /etc/sudoers.d/ldap-users

# 启动
sudo systemctl restart sssd
sudo pam-auth-update
```

如果修改了配置规则，且开启了ldap_id_mapping 可能会有数据库缓存问题。可以手动清空缓存。

```bash
# 删除数据库缓存
sudo rm -f /var/lib/sss/db/*

# 删除内存映射缓存 (这是导致配置不生效的元凶)
sudo rm -f /var/lib/sss/mc/*

sudo systemctl restart sssd
```

## OIDC for debian

可使用 [teleport](https://goteleport.com/)
