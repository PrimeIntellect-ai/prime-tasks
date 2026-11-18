#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx gcc gunicorn
    pip3 install pytest flask gunicorn

    # Create directories
    mkdir -p /home/user/nginx/client_body
    mkdir -p /home/user/nginx/fastcgi_temp
    mkdir -p /home/user/nginx/proxy_temp
    mkdir -p /home/user/nginx/scgi_temp
    mkdir -p /home/user/nginx/uwsgi_temp
    mkdir -p /home/user/app
    mkdir -p /app

    # Create Nginx config
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log stderr;
pid /home/user/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log off;
    client_body_temp_path /home/user/nginx/client_body;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    proxy_temp_path /home/user/nginx/proxy_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;

    server {
        listen 127.0.0.1:8080;

        location / {
            proxy_pass http://unix:/home/user/run/wrong.sock;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

    # Create Flask app
    cat << 'EOF' > /home/user/app/server.py
from flask import Flask, request, Response
import subprocess

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process():
    data = request.get_data(as_text=True)
    try:
        result = subprocess.run(
            ['python3', '/home/user/processor.py'],
            input=data,
            text=True,
            capture_output=True,
            check=True
        )
        return Response(result.stdout, status=200, mimetype='text/plain')
    except Exception as e:
        return Response(str(e), status=500, mimetype='text/plain')

if __name__ == '__main__':
    app.run()
EOF

    # Create Oracle C source and compile
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char *buffer = NULL;
    size_t total_len = 0;
    char temp[1024];
    while (fgets(temp, sizeof(temp), stdin)) {
        size_t l = strlen(temp);
        buffer = realloc(buffer, total_len + l + 1);
        memcpy(buffer + total_len, temp, l);
        total_len += l;
        buffer[total_len] = '\0';
    }

    if (buffer == NULL) return 0;

    for (size_t i = 0; i < total_len; i++) {
        if (buffer[i] >= 'a' && buffer[i] <= 'z') {
            buffer[i] = ((buffer[i] - 'a' + 13) % 26) + 'a';
        } else if (buffer[i] >= 'A' && buffer[i] <= 'Z') {
            buffer[i] = ((buffer[i] - 'A' + 13) % 26) + 'A';
        }
    }

    for (size_t i = 0; i < total_len / 2; i++) {
        char t = buffer[i];
        buffer[i] = buffer[total_len - 1 - i];
        buffer[total_len - 1 - i] = t;
    }

    printf("%s", buffer);
    free(buffer);
    return 0;
}
EOF
    gcc -O2 /app/oracle.c -o /app/oracle_processor
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
