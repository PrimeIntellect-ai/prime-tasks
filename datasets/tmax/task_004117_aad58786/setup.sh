#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server gcc libfcgi-dev spawn-fcgi procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/backend
    mkdir -p /home/user/app/nginx
    mkdir -p /home/user/app/redis
    mkdir -p /home/user/app/logs

    cat << 'EOF' > /home/user/app/backend/server.c
#include <fcgi_stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    while (FCGI_Accept() >= 0) {
        char *query = getenv("QUERY_STRING");
        char *uri = getenv("DOCUMENT_URI");

        if (uri && strcmp(uri, "/login") == 0) {
            char *redirect_url = NULL;
            if (query && strncmp(query, "redirect_url=", 13) == 0) {
                redirect_url = query + 13;
            }
            if (!redirect_url) redirect_url = "/home";

            printf("Status: 302 Found\r\n");
            printf("Location: %s\r\n\r\n", redirect_url);
        } else if (uri && strcmp(uri, "/error") == 0) {
            char *error_msg = "Unknown error";
            if (query && strncmp(query, "error_msg=", 10) == 0) {
                error_msg = query + 10;
            }
            printf("Content-type: text/html\r\n\r\n");
            printf("<html><body>Error: %s</body></html>\n", error_msg);
        } else {
            printf("Content-type: text/plain\r\n\r\n");
            printf("Hello\n");
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /dev/null;
pid /tmp/nginx.pid;
events { worker_connections 1024; }
http {
    access_log off;
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;

    include /home/user/app/nginx/block.conf;

    server {
        listen 8080;
        location / {
            fastcgi_pass 127.0.0.1:9000;
            include /etc/nginx/fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        }
    }
}
EOF

    touch /home/user/app/nginx/block.conf

    cat << 'EOF' > /home/user/app/redis/redis.conf
bind 0.0.0.0
port 6379
daemonize yes
EOF

    cat << 'EOF' > /home/user/app/logs/auth.log
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 198.51.100.42
Failed login for user admin from 1.2.3.4
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
pkill -f nginx
pkill -f server
pkill -f redis-server
sleep 1
cd /home/user/app/backend
gcc server.c -o server -lfcgi
spawn-fcgi -p 9000 ./server
redis-server /home/user/app/redis/redis.conf
nginx -c /home/user/app/nginx/nginx.conf &
EOF

    chmod +x /home/user/app/start_services.sh
    chmod -R 777 /home/user
