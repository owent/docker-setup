# nginx

```conf
daemon off; # For docker
user  nginx;
worker_processes 16;

error_log  /var/log/nginx/nginx-error.log warn;
pid        /var/run/nginx.pid;


events {
    use epoll;
    worker_connections 102400;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    gzip on;
    gzip_min_length  1k;
    gzip_buffers     16 64k;
    gzip_http_version 1.0;
    gzip_comp_level 5;
    gzip_types       text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript application/javascript;
    gzip_vary on;

    # remove nginx version
    server_tokens off;

    # remove nginx header: X-Powered-By header
    fastcgi_hide_header X-Powered-By;

    ssl_protocols TLSv1.2 TLSv1.3; # omit SSLv3 because of POODLE (CVE-2014-3566)
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    # add_header Strict-Transport-Security "max-age=15768000; includeSubdomains; preload"; # HSTS, 180days
    add_header X-Content-Type-Options nosniff;

    # @see https://mozilla.github.io/server-side-tls/ssl-config-generator/
    # We use intermediate mode
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;
    ssl_dhparam /etc/nginx/dhparam.pem;
    ssl_stapling on;
    ssl_stapling_verify on;

    include /etc/nginx/conf.d/*.conf;
}
```
