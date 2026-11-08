#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx git build-essential acl
pip3 install pytest

# Create the user
useradd -m -s /bin/bash user || true

# Setup Nginx config
cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /tmp/access.log;
    error_log /tmp/error.log;
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;

    server {
        listen 8080;
        server_name localhost;
        root /home/user/www;
        index index.html index.htm;

        location / {
            try_files $uri $uri/ =404;
        }

        location /render {
            fastcgi_pass 127.0.0.1:9000;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        }
    }
}
EOF

# Setup Git repo
mkdir -p /home/user/site.git
cd /home/user/site.git
git init --bare

# Setup deploy directory and intentionally mess up permissions
mkdir -p /home/user/deploy/current
chmod 700 /home/user/deploy

# Setup renderer and corpora
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

# Create a C program that segfaults on the specific payload
cat << 'EOF' > /app/renderer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char buffer[1024];
    while (fgets(buffer, sizeof(buffer), f)) {
        char *ptr = strstr(buffer, "[!!!EXEC_CTX:");
        if (ptr) {
            char *end = strstr(ptr, "}}");
            if (!end) {
                // Segfault
                int *p = NULL;
                *p = 42;
            }
        }
    }
    fclose(f);
    return 0;
}
EOF
gcc -o /app/renderer /app/renderer.c
strip /app/renderer

# Create clean files
cat << 'EOF' > /app/corpus/clean/file1.md
# Hello World
This is a safe file.
EOF

cat << 'EOF' > /app/corpus/clean/file2.md
# Safe File
[!!!EXEC_CTX: safe_context }}
EOF

# Create evil files
cat << 'EOF' > /app/corpus/evil/file1.md
# Evil File
[!!!EXEC_CTX: malicious_payload
EOF

cat << 'EOF' > /app/corpus/evil/file2.md
# Another Evil File
Some text [!!!EXEC_CTX: missing_end_tag
EOF

chmod -R 777 /home/user
chmod -R 777 /app
