# 自定义 CA 证书目录
#
# 将您的自签名 CA 证书 (.crt 文件) 放在此目录中
# 构建镜像时会自动复制到容器并更新证书链
#
# 示例:
#   cp /usr/local/share/ca-certificates/my-ca.crt ./ca-certificates/
#
# 注意: 证书文件必须以 .crt 结尾
