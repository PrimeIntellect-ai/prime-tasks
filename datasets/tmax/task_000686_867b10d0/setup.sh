#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx spawn-fcgi libfcgi-dev curl openssl
    pip3 install pytest

    # Create directories
    mkdir -p /app/bin /app/nginx /app/config /app/certs /app/corpus/evil /app/corpus/clean /app/backend

    # Create auth_module source and compile
    cat << 'EOF' > /tmp/auth_module.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    // MD5 hash of "admin123" is 0192023a7bbd73250516f069df18b500
    if (strcmp(argv[1], "0192023a7bbd73250516f069df18b500") == 0) {
        printf("Access granted.\n");
        return 0;
    }
    printf("Access denied.\n");
    return 1;
}
EOF
    gcc -o /app/bin/auth_module /tmp/auth_module.c
    rm /tmp/auth_module.c

    # Create dummy backend
    cat << 'EOF' > /app/backend/backend.c
#include <fcgi_stdio.h>
#include <stdlib.h>

int main(void) {
    while (FCGI_Accept() >= 0) {
        printf("Content-type: text/plain\r\n\r\n");
        printf("pong");
    }
    return 0;
}
EOF
    gcc -o /app/backend/backend /app/backend/backend.c -lfcgi

    # Create Nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        server_name rotation.local;
        location /ping {
            fastcgi_pass 127.0.0.1:9000;
            include fastcgi_params;
        }
    }
}
EOF

    # Create start script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
spawn-fcgi -p 9000 -n /app/backend/backend &
nginx -c /app/nginx/nginx.conf -g "daemon off;" &
wait
EOF
    chmod +x /app/start.sh

    # Populate corpus
    touch /app/corpus/clean/cert_2023.pem
    touch /app/corpus/clean/key-file.txt
    touch /app/corpus/evil/../../../etc/passwd
    touch /app/corpus/evil/%2e%2e%2f%2e%2e%2f
    touch "/app/corpus/evil/valid.txt%00.jpg"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
