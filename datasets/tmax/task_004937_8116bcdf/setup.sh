#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nginx redis-server gcc
    pip3 install pytest

    mkdir -p /app

    # Create the mock Go API
    cat << 'EOF' > /app/go_api.py
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/ping':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'pong')
        else:
            self.send_response(404)
            self.end_headers()
HTTPServer(('127.0.0.1', 8081), Handler).serve_forever()
EOF

    # Create broken nginx.conf
    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/v1/ {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

    # Create oracle decoder in C
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *hex = argv[1];
    size_t len = strlen(hex);
    if (len % 2 != 0) return 1;
    size_t out_len = len / 2;
    unsigned char *bytes = malloc(out_len);
    for (size_t i = 0; i < out_len; i++) {
        sscanf(hex + 2*i, "%2hhx", &bytes[i]);
    }
    for (size_t i = 0; i < out_len; i++) {
        bytes[i] ^= 0x5A;
    }
    for (size_t i = 0; i < out_len / 2; i++) {
        unsigned char tmp = bytes[i];
        bytes[i] = bytes[out_len - 1 - i];
        bytes[out_len - 1 - i] = tmp;
    }
    fwrite(bytes, 1, out_len, stdout);
    free(bytes);
    return 0;
}
EOF
    gcc /app/oracle.c -o /app/oracle_decoder
    rm /app/oracle.c
    chmod +x /app/oracle_decoder

    # Create start script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx.conf
python3 /app/go_api.py &
sleep 1
EOF
    chmod +x /app/start.sh

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
