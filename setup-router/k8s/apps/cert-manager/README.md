# cert-manager

## Install

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true
```

## Set secret for ACME and dns solver

```bash
# https://app.zerossl.com/developer
# - EAB Credentials for ACME Clients
kubectl create secret generic \
       zerossl-eabsecret-example.org \
       --namespace=cert-manager \
       --from-literal=secret='EAM_TOKEN_FROM_ZEROSSL'

# Requires
# - Permissions:
#   - Zone - DNS - Edit
#   - Zone - Zone - Read
# - Zone Resources
#   - Include - All Zones
kubectl create secret generic \
       cloudflare-apikey-secret-example.org \
       --namespace=cert-manager \
       --from-literal=api-token='API_TOKEN_FROM_CLOUDFLARE'

```

## Utilities

```bash
# 查询可用的签证Issuer
kubectl get -n cert-manager ciss -o wide # clusterissuers
kubectl get -n cert-manager iss -o wide # issuers

kubectl logs -n cert-manager deployment/cert-manager
# 短期内出现 propagation check failed" err="DNS record for \"example.org\" not yet propagated 可能是在等待验证

# 证书状态
kubectl get certificate -o wide
kubectl describe certificate $certificate_name

# 证书请求/内容
kubectl get certificaterequest -o wide
kubectl describe certificaterequest $CertificateRequestName

# 查看所有相关的 Challenge 资源(创建过程)
kubectl get challenges

# 查看具体的 Challenge 详情
kubectl describe challenge $challenge_name

# 提交root CA证书
kubectl -n cert-manager create secret tls root-ca-secret \
  --cert=tls.crt \
  --key=tls.key \
  --dry-run=client --save-config -o yaml | kubectl apply -f -
```
