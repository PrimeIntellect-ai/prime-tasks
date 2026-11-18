#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx curl
    pip3 install pytest

    mkdir -p /home/user/workspace/nginx_prefix

    cat << 'EOF' > /home/user/workspace/libcompute.c
#include <stdint.h>

double process_records(const unsigned char* data, int length) {
    if (length % 6 != 0) return -1.0;
    double sum = 0.0;
    for (int i = 0; i < length; i += 6) {
        uint16_t id = *(uint16_t*)(data + i);
        float value = *(float*)(data + i + 2);
        sum += (double)(id * value);
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/workspace/app.py
import http.server
import json
import ctypes
import struct

lib = ctypes.CDLL('./libcompute.so')
# BUG: Missing argtypes and restype
# lib.process_records.argtypes = [ctypes.c_char_p, ctypes.c_int]
# lib.process_records.restype = ctypes.c_double

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/process':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            records = json.loads(post_data)

            binary_data = bytearray()
            for r in records:
                # BUG: serialization missing or incorrect
                pass 

            # BUG: Calling C func incorrectly
            res = lib.process_records(bytes(binary_data), len(binary_data))

            self.send_response(200)
            self.end_headers()
            self.wfile.write(f"{res:.4f}".encode())

if __name__ == '__main__':
    server = http.server.HTTPServer(('127.0.0.1', 8080), Handler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/workspace/nginx.conf
worker_processes 1;
pid /home/user/workspace/nginx_prefix/nginx.pid;
error_log /home/user/workspace/nginx_prefix/error.log;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/workspace/nginx_prefix/access.log;
    client_body_temp_path /home/user/workspace/nginx_prefix/client_body;
    proxy_temp_path /home/user/workspace/nginx_prefix/proxy;
    fastcgi_temp_path /home/user/workspace/nginx_prefix/fastcgi;
    uwsgi_temp_path /home/user/workspace/nginx_prefix/uwsgi;
    scgi_temp_path /home/user/workspace/nginx_prefix/scgi;

    server {
        listen 127.0.0.1:8000;

        # BUG: incorrect location and proxy_pass
        location /api/ {
            proxy_pass http://127.0.0.1:8080/;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
