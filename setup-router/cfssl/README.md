# cfssl 使用备注

## 下载最新版本

```bash
bash ./download-bins.sh
```

## 查看证书信息

```bash
cfssl certinfo -cert child-ca.pem 
# cfssl certinfo -csr child-ca.csr
# cfssl certinfo -domain domain_name
# cfssl certinfo -db-config=db.cfg -aki=key_identifier -sn serial
```

## 生成CA证书

```bash
# 根CA
cfssl gencert -initca -config=./ca-config.json -profile=root-ca-30y ./csr-root-ca.json | cfssljson -bare ./root-ca -

SUBCA_NAME=child-ca
# 子CA(子CA和根CA的Subject必须不一样，通常改CN参数即可)
cfssl genkey ./csr-$SUBCA_NAME.json | cfssljson -bare $SUBCA_NAME
cfssl sign -ca root-ca.pem -ca-key root-ca-key.pem -config=./ca-config.json -profile=sub-ca-5y $SUBCA_NAME.csr | cfssljson -bare $SUBCA_NAME

# 准备fullchain的前缀
cat root-ca.pem $SUBCA_NAME.pem > fullchain.prefix.cer

# 验证证书链
openssl verify -CAfile root-ca.pem $SUBCA_NAME.pem
```

## 生成服务器证书

```bash
USECA_NAME=child-ca
APP_NAME=etcd
cfssl gencert -ca ./$USECA_NAME.pem                             \
            -ca-key ./$USECA_NAME-key.pem                       \
            -config ./ca-config.json -profile=server            \
            -hostname "使用者名称，多个用逗号分隔"              \
            ./csr-endpoint.json | cfssljson -bare ./$APP_NAME -

cat fullchain.prefix.cer ./$APP_NAME.pem > fullchain.$APP_NAME.cer

# 验证证书链
openssl verify -CAfile root-ca.pem $SUBCA_NAME.pem
```

## 生成客户端证书

```bash
USECA_NAME=child-ca
APP_NAME=etcd
cfssl gencert -ca ./$USECA_NAME.pem                             \
            -ca-key ./$USECA_NAME-key.pem                       \
            -config ./ca-config.json -profile=client            \
            -hostname "使用者名称，多个用逗号分隔"              \
            ./csr-endpoint.json | cfssljson -bare ./$APP_NAME -

# 验证证书链
openssl verify -CAfile root-ca.pem $SUBCA_NAME.pem
```

## 生成对端证书，即服务器认证+客户端认证

```bash
USECA_NAME=child-ca
APP_NAME=etcd
cfssl gencert -ca ./$USECA_NAME.pem                             \
            -ca-key ./$USECA_NAME-key.pem                       \
            -config ./ca-config.json -profile=peer              \
            -hostname "使用者名称，多个用逗号分隔"              \
            ./csr-endpoint.json | cfssljson -bare ./$APP_NAME -


# 验证证书链
openssl verify -CAfile root-ca.pem $SUBCA_NAME.pem
```

## Usages参数说明

```md
+ Key Usages
    + signing - 数字签名 (x509.KeyUsageDigitalSignature)
    + digital signature - 数字签名的完整名称
    + content commitment - 内容承诺（不可否认性）
    + key encipherment - 密钥加密，用于加密对称密钥
    + key agreement - 密钥协商
    + data encipherment - 数据加密
    + cert sign - 证书签名，用于CA证书
    + crl sign - CRL（证书撤销列表）签名
    + encipher only - 仅加密
    + decipher only - 仅解密
+ Ext Key Usages
    + any
    + server auth - 服务器身份验证（TLS服务器证书）
    + client auth - 客户端身份验证（TLS客户端证书）
    + code signing - 代码签名
    + email protection - 电子邮件保护
    + s/mime - S/MIME
    + ipsec end system - IPSec终端系统
    + ipsec tunnel - IPSec隧道
    + ipsec user - IPSec用户
    + timestamping - 时间戳
    + ocsp signing - OCSP签名
    + microsoft sgc - Microsoft SGC
    + netscape sgc - Netscape SGC
```

## 证书轮换周期

- 2026年3月14日前：证书有效期最长为398天。
- 2027年3月14日前：证书有效期最长缩短至200天。
- 2028年3月14日前：证书有效期最长缩短至100天。
- 2028年3月15日后：证书有效期最长缩短至47天。
