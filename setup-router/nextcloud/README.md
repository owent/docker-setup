# nextcloue setup

1. Set environment `ADMIN_USENAME`, `ADMIN_TOKEN`, `NEXTCLOUD_DATA_DIR`, `NEXTCLOUD_APPS_DIR`, `NEXTCLOUD_ETC_DIR`

  > `mkdir -p $NEXTCLOUD_DATA_DIR $NEXTCLOUD_APPS_DIR $NEXTCLOUD_ETC_DIR && chmod 770 $NEXTCLOUD_DATA_DIR $NEXTCLOUD_APPS_DIR $NEXTCLOUD_ETC_DIR`

1. Use the final domain (e.g. `home.x-ha.com`) to setup nextcloud
1. Modify/Add settings in `config.php`
  >
  > ```php
  > $CONFIG = array(
  >  'trusted_domains' => array ( 0 => 'LOCAL_IP:LOCAL_PORT', ),
  >  'overwritehost' => 'home.x-ha.com:6443',
  >  'overwriteprotocol' => 'https',
  >  'trusted_proxies' => array ( 0 => '0.0.0.0/32', ),
  >  'overwrite.cli.url' => 'https://home.x-ha.com:6443',
  >  'default_phone_region' => 'CN',
  >  'versions_retention_obligation' => 'auto, 30',
  >  'trashbin_retention_obligation' => 'auto, 180',
  > );
  > ```
  >
1. Set and mount nginx paths:
  >
  > + Set root of `nextcloud-fpm.nginx.conf` to `/usr/share/nginx/html/nextcloud`
  > + Mount `$NEXTCLOUD_REVERSE_ROOT_DIR/nextcloud` -> `/usr/share/nginx/html/nextcloud`.
  > + Mount `$NEXTCLOUD_APPS_DIR` -> `/usr/share/nginx/html/nextcloud/custom_apps`.
  >

## occ commands

```bash
podman exec -u <run user> <container name> env PHP_MEMORY_LIMIT=1024M php occ ...

# Examples
podman exec -u www-data nextcloud env PHP_MEMORY_LIMIT=1024M php occ app:install documentserver_community
```

## postgresql

```bash
psql -h localhost -U postgres

  CREATE USER nextcloud WITH PASSWORD '<密码>' CREATEDB;
  CREATE DATABASE nextcloud TEMPLATE template0 ENCODING 'UTF8';
  ALTER DATABASE nextcloud OWNER TO nextcloud;
  GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;
  GRANT ALL PRIVILEGES ON SCHEMA public TO nextcloud;

  \q
```

## 连接onlyoffice

注意: 如果局域网跨机器需要设置DNS，本地解析指向内网地址，外网解析走正常DNS/DDNS 。否则跨网点网络很不稳定。

## LDAP账户清理

```bash
sudo -E -u podman exec -u www-data nextcloud php occ ldap:show-remnants
sudo -E -u podman exec -u www-data nextcloud php occ user:delete USER_NAME
```

## LLDAP账户配置: 

LDAP集成见 <https://github.com/lldap/lldap/blob/main/example_configs/nextcloud.md>

## Authentik LDAP账户配置: 

- `php occ ldap:show-config`
- `php occ ldap:test-config s01`
- `php occ ldap:check-user [username]`


php occ ldap:set-config s01 ldapHost ldaps://ldap.example.org:6636
php occ ldap:set-config s01 ldapPort 6636
php occ ldap:set-config s01 ldapTLS 1
php occ ldap:set-config s01 ldapAgentName "cn=ldap-bind,ou=users,dc=example,dc=org"
php occ ldap:set-config s01 ldapAgentPassword "<密码>"
php occ ldap:set-config s01 ldapBase "dc=example,dc=org"
php occ ldap:set-config s01 ldapBaseGroups "ou=groups,dc=example,dc=org"
php occ ldap:set-config s01 ldapBaseUsers "ou=users,dc=example,dc=org"
php occ ldap:set-config s01 ldapGidNumber gidNumber
# ldap_uniq 是authentik特有字段，其他平台的可能是其他字段，可以fallback成cn,name等
php occ ldap:set-config s01 ldapExpertUsernameAttr cn
php occ ldap:set-config s01 ldapExpertUUIDUserAttr uid
php occ ldap:set-config s01 ldapExpertUUIDGroupAttr uid
php occ ldap:set-config s01 ldapEmailAttribute mail
php occ ldap:set-config s01 ldapGroupFilter "(&(objectClass=group)(|(cn=admin)(cn=staff)(cn=external-collaborator)))"
php occ ldap:set-config s01 ldapGroupFilterGroups "admin;staff;external-collaborator"
php occ ldap:set-config s01 ldapGroupFilterObjectclass group
# ldapGroupMemberAssocAttr 默认值是 member 和 useMemberOfToDetectMembership 冲突，会导致用户组拉取抖动
php occ ldap:set-config s01 ldapGroupMemberAssocAttr ""
php occ ldap:set-config s01 ldapLoginFilter "(&(&(objectClass=user)(|(memberOf=cn=staff,ou=groups,dc=example,dc=org)(memberOf=cn=external-collaborator,ou=groups,dc=example,dc=org)))(cn=%uid))"
php occ ldap:set-config s01 ldapUserFilter "(&(objectClass=user)(|(memberOf=cn=staff,ou=groups,dc=example,dc=org)(memberOf=cn=external-collaborator,ou=groups,dc=example,dc=org)))"
php occ ldap:set-config s01 ldapUserDisplayName displayName
php occ ldap:set-config s01 ldapUserDisplayName2 cn
php occ ldap:set-config s01 ldapUserFilterObjectclass user
# cn 是authentik和大多数LDAP服务都支持的字段，其他平台的可能是其他字段，可以fallback成name,uid,ldap_uniq等
php occ ldap:set-config s01 homeFolderNamingRule "attr:cn"
php occ ldap:set-config s01 ldapGroupDisplayName cn
php occ ldap:set-config s01 ldapUserFilterMode 1
php occ ldap:set-config s01 ldapNestedGroups 0
php occ ldap:set-config s01 ldapPagingSize 500
php occ ldap:set-config s01 ldapUuidGroupAttribute auto
php occ ldap:set-config s01 ldapUuidUserAttribute auto
php occ ldap:set-config s01 ldapLoginFilterEmail 0
php occ ldap:set-config s01 ldapLoginFilterUsername 1
php occ ldap:set-config s01 ldapMatchingRuleInChainState unknown
php occ ldap:set-config s01 ldapGroupFilterMode 0
php occ ldap:set-config s01 turnOnPasswordChange 0
php occ ldap:set-config s01 ldapCacheTTL 1800
php occ ldap:set-config s01 ldapExperiencedAdmin 0
php occ ldap:set-config s01 ldapUserFilterMode 0
# 如果上面使用 ldapGroupMemberAssocAttr , 这里需要设置成0, 然后移除所有 memberOf 相关的 filter,组限制改用基于 DN 的 group filter
php occ ldap:set-config s01 useMemberOfToDetectMembership 1
php occ ldap:set-config s01 ldapConfigurationActive 1

```rst
+-------------------------------+----------------------------------------------------------------------------------------------------------------------------------------------+
| Configuration                 | s01                                                                                                                                          |
+-------------------------------+----------------------------------------------------------------------------------------------------------------------------------------------+
| hasMemberOfFilterSupport      | 0                                                                                                                                            |
| homeFolderNamingRule          | attr:cn                                                                                                                               |
| lastJpegPhotoLookup           | 0                                                                                                                                            |
| ldapAdminGroup                |                                                                                                                                              |
| ldapAgentName                 | cn=ldap-bind,ou=users,dc=example,dc=org                                                                                                         |
| ldapAgentPassword             | ***                                                                                                                                          |
| ldapAttributeAddress          |                                                                                                                                              |
| ldapAttributeAnniversaryDate  |                                                                                                                                              |
| ldapAttributeBiography        |                                                                                                                                              |
| ldapAttributeBirthDate        |                                                                                                                                              |
| ldapAttributeFediverse        |                                                                                                                                              |
| ldapAttributeHeadline         |                                                                                                                                              |
| ldapAttributeOrganisation     |                                                                                                                                              |
| ldapAttributePhone            |                                                                                                                                              |
| ldapAttributePronouns         |                                                                                                                                              |
| ldapAttributeRole             |                                                                                                                                              |
| ldapAttributeTwitter          |                                                                                                                                              |
| ldapAttributeWebsite          |                                                                                                                                              |
| ldapAttributesForGroupSearch  |                                                                                                                                              |
| ldapAttributesForUserSearch   |                                                                                                                                              |
| ldapBackgroundHost            |                                                                                                                                              |
| ldapBackgroundPort            |                                                                                                                                              |
| ldapBackupHost                |                                                                                                                                              |
| ldapBackupPort                |                                                                                                                                              |
| ldapBase                      | dc=example,dc=org                                                                                                                               |
| ldapBaseGroups                | ou=groups,dc=example,dc=org                                                                                                                     |
| ldapBaseUsers                 | ou=users,dc=example,dc=org                                                                                                                      |
| ldapCacheTTL                  | 1800                                                                                                                                         |
| ldapConfigurationActive       | 1                                                                                                                                            |
| ldapConnectionTimeout         | 15                                                                                                                                           |
| ldapDefaultPPolicyDN          |                                                                                                                                              |
| ldapDynamicGroupMemberURL     |                                                                                                                                              |
| ldapEmailAttribute            | mail                                                                                                                                         |
| ldapExperiencedAdmin          | 0                                                                                                                                            |
| ldapExpertUUIDGroupAttr       | uid                                                                                                                                          |
| ldapExpertUUIDUserAttr        | uid                                                                                                                                          |
| ldapExpertUsernameAttr        | cn                                                                                                                                           |
| ldapExtStorageHomeAttribute   |                                                                                                                                              |
| ldapGidNumber                 | gidnumber                                                                                                                                    |
| ldapGroupDisplayName          | cn                                                                                                                                           |
| ldapGroupFilter               | (&(objectClass=group)(|(cn=admin)(cn=staff)(cn=external-collaborator)))                                                                      |
| ldapGroupFilterGroups         | admin;staff;external-collaborator                                                                                                            |
| ldapGroupFilterMode           | 0                                                                                                                                            |
| ldapGroupFilterObjectclass    | group                                                                                                                                        |
| ldapGroupMemberAssocAttr      | member                                                                                                                                       |
| ldapHost                      | ldaps://ldap.example.org                                                                                                                        |
| ldapIgnoreNamingRules         |                                                                                                                                              |
| ldapLoginFilter               | (&(&(objectClass=user)(|(memberOf=cn=staff,ou=groups,dc=example,dc=org)(memberOf=cn=external-collaborator,ou=groups,dc=example,dc=org)))(cn=%uid)) |
| ldapLoginFilterAttributes     |                                                                                                                                              |
| ldapLoginFilterEmail          | 0                                                                                                                                            |
| ldapLoginFilterMode           | 0                                                                                                                                            |
| ldapLoginFilterUsername       | 1                                                                                                                                            |
| ldapMatchingRuleInChainState  | unknown                                                                                                                                      |
| ldapNestedGroups              | 0                                                                                                                                            |
| ldapOverrideMainServer        |                                                                                                                                              |
| ldapPagingSize                | 500                                                                                                                                          |
| ldapPort                      | 6636                                                                                                                                         |
| ldapQuotaAttribute            |                                                                                                                                              |
| ldapQuotaDefault              |                                                                                                                                              |
| ldapTLS                       | 1                                                                                                                                            |
| ldapUserAvatarRule            | default                                                                                                                                      |
| ldapUserDisplayName           | displayName                                                                                                                                  |
| ldapUserDisplayName2          | cn                                                                                                                                           |
| ldapUserFilter                | (&(objectClass=user)(|(memberOf=cn=staff,ou=groups,dc=example,dc=org)(memberOf=cn=external-collaborator,ou=groups,dc=example,dc=org)))             |
| ldapUserFilterGroups          |                                                                                                                                              |
| ldapUserFilterMode            | 0                                                                                                                                            |
| ldapUserFilterObjectclass     | user                                                                                                                                         |
| ldapUuidGroupAttribute        | auto                                                                                                                                         |
| ldapUuidUserAttribute         | auto                                                                                                                                         |
| markRemnantsAsDisabled        | 0                                                                                                                                            |
| turnOffCertCheck              | 0                                                                                                                                            |
| turnOnPasswordChange          | 0                                                                                                                                            |
| useMemberOfToDetectMembership | 1                                                                                                                                            |
+-------------------------------+----------------------------------------------------------------------------------------------------------------------------------------------+
```
