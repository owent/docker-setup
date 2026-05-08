# keepalived

keepalived没有官方docker镜像，建议直接用发行版内自带的版本。

## 配置邮件通知

keepalived 状态切换邮件由 `/etc/keepalived/notify-state.sh` 调用系统 `mail` 命令发送。
`mail` 通过本机 `msmtp-mta` 使用 `/etc/msmtprc` 里的 `default` 账号投递邮件，SMTP/SSL/465
服务器、账号和密码等鉴权信息只保存在系统级 `/etc/msmtprc`，不要放在 keepalived 配置目录里。

```bash
cp /etc/keepalived/mail.env.example /etc/keepalived/mail.env
vim /etc/keepalived/mail.env
```

`/etc/keepalived/mail.env` 只放收件人等非鉴权项：

```bash
KEEPALIVED_MAIL_ENABLED=1
KEEPALIVED_MAIL_TO=ops@example.com
```

如果直接在发行版宿主机运行 keepalived，而不是使用本目录里的容器镜像，需要先安装依赖包：

```bash
sudo apt install -y  mailutils msmtp msmtp-mta
```

手动配置系统级 `/etc/msmtprc` 并测试邮件发送：

```bash
### 配置 SMTP 转发 （/etc/msmtprc）。
### 注意: account 得是 default ,mail/sendmail 调用 msmtp 时，默认找的是 default 账号。
echo "
defaults
auth           on
tls            on
tls_starttls   off
tls_trust_file /etc/ssl/certs/ca-certificates.crt
syslog LOG_MAIL

account default
host           smtp.exmail.qq.com
port           465
auth           on
tls            on
tls_starttls   off
tls_trust_file /etc/ssl/certs/ca-certificates.crt

user           admin@owent.net
from           admin@owent.net
password       your_smtp_password
" | sudo tee -a /etc/msmtprc
sudo chmod 600 /etc/msmtprc
### 测试发信
echo "keepalived mail test" | sudo mail -s "test" ops@example.com
```
