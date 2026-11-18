#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx rustc systemd cron curl
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/app/nginx_temp/client_body
    mkdir -p /home/user/app/nginx_temp/proxy
    mkdir -p /home/user/app/nginx_temp/fastcgi
    mkdir -p /home/user/app/nginx_temp/uwsgi
    mkdir -p /home/user/app/nginx_temp/scgi
    mkdir -p /home/user/app/src/
    mkdir -p /home/user/.config/systemd/user/

    # Create nginx.conf
    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
error_log /home/user/app/error.log;
pid /home/user/app/nginx.pid;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/app/nginx_temp/client_body;
    proxy_temp_path /home/user/app/nginx_temp/proxy;
    fastcgi_temp_path /home/user/app/nginx_temp/fastcgi;
    uwsgi_temp_path /home/user/app/nginx_temp/uwsgi;
    scgi_temp_path /home/user/app/nginx_temp/scgi;

    access_log /home/user/app/access.log;

    server {
        listen 9090;
        server_name 127.0.0.1;

        location /transform {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

    # Create server.py
    cat << 'EOF' > /home/user/app/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
import subprocess

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        transformer_path = os.environ.get('TRANSFORMER_PATH')
        if not transformer_path or not os.path.exists(transformer_path):
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Internal Server Error: Transformer not found")
            return

        try:
            p = subprocess.Popen([transformer_path], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            out, err = p.communicate(input=body)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(out)
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), RequestHandler)
    server.serve_forever()
EOF

    # Create and compile oracle_transformer
    cat << 'EOF' > /tmp/oracle.rs
use std::io::{self, Read, Write};

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).unwrap();

    let mut out = Vec::new();
    let mut i = 0;
    while i < input.len() {
        let c = input[i];
        if c >= b'A' && c <= b'Z' {
            let mut count = 1;
            while i + count < input.len() && input[i + count] == c {
                count += 1;
            }
            out.extend_from_slice(format!("{}{}", count, c as char).as_bytes());
            i += count;
        } else {
            out.push(c);
            i += 1;
        }
    }
    io::stdout().write_all(&out).unwrap();
}
EOF
    rustc /tmp/oracle.rs -o /home/user/oracle_transformer
    rm /tmp/oracle.rs

    chmod -R 777 /home/user
