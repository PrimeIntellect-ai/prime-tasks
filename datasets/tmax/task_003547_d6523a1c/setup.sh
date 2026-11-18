#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx redis-server
    pip3 install pytest flask redis

    mkdir -p /app/bin
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main() {
    unsigned char header[5];
    if (fread(header, 1, 5, stdin) != 5 || memcmp(header, "DOCW\x01", 5) != 0) {
        fprintf(stderr, "INVALID\n");
        return 1;
    }
    while (1) {
        unsigned char type;
        if (fread(&type, 1, 1, stdin) != 1) break;
        if (type == 0xFF) return 0;
        unsigned char len_bytes[2];
        if (fread(len_bytes, 1, 2, stdin) != 2) break;
        uint16_t length = len_bytes[0] | (len_bytes[1] << 8);
        unsigned char *payload = malloc(length);
        if (length > 0 && fread(payload, 1, length, stdin) != length) {
            free(payload);
            break;
        }
        if (type == 0x01 && length > 0) {
            fwrite(payload, 1, length, stdout);
        }
        free(payload);
    }
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/bin/oracle_extractor
    rm /tmp/oracle.c

    mkdir -p /home/user/doc_system

    cat << 'EOF' > /home/user/doc_system/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/doc_system/error.log;
pid /home/user/doc_system/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/doc_system/access.log;
    client_body_temp_path /home/user/doc_system/client_body;
    proxy_temp_path /home/user/doc_system/proxy_temp;
    fastcgi_temp_path /home/user/doc_system/fastcgi_temp;
    uwsgi_temp_path /home/user/doc_system/uwsgi_temp;
    scgi_temp_path /home/user/doc_system/scgi_temp;
    server {
        listen 8080;
        location /api/ {
            # missing configuration here
        }
    }
}
EOF

    cat << 'EOF' > /home/user/doc_system/flask_app.py
from flask import Flask, request
import subprocess
import redis

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/api/upload', methods=['POST'])
def upload():
    data = request.get_data()
    result = subprocess.run(['/app/bin/oracle_extractor'], input=data, capture_output=True)
    if result.returncode == 0:
        r.set('last_doc', result.stdout)
        return result.stdout, 200
    else:
        return "Error", 400

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/doc_system/redis.conf
bind 127.0.0.1
port 6379
dir /home/user/doc_system/
daemonize yes
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
