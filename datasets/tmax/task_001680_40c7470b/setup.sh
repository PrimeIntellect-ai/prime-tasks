#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/nginx/logs
    mkdir -p /home/user/app/nginx/temp/client_body
    mkdir -p /home/user/app/nginx/temp/proxy
    mkdir -p /home/user/app/nginx/temp/fastcgi
    mkdir -p /home/user/app/nginx/temp/uwsgi
    mkdir -p /home/user/app/nginx/temp/scgi
    mkdir -p /home/user/app/operator/src

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
python3 -c "
import http.server
import socketserver
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'backend-a')
socketserver.TCPServer(('127.0.0.1', 8081), Handler).serve_forever()
" &

python3 -c "
import http.server
import socketserver
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'backend-b')
socketserver.TCPServer(('127.0.0.1', 8082), Handler).serve_forever()
" &

nginx -c /home/user/app/nginx/nginx.conf
EOF
    chmod +x /home/user/app/start_services.sh

    cat << 'EOF' > /home/user/app/nginx/nginx.conf
pid /home/user/app/nginx/nginx.pid;
error_log /home/user/app/nginx/logs/error.log;
events {}
http {
    client_body_temp_path /home/user/app/nginx/temp/client_body;
    proxy_temp_path /home/user/app/nginx/temp/proxy;
    fastcgi_temp_path /home/user/app/nginx/temp/fastcgi;
    uwsgi_temp_path /home/user/app/nginx/temp/uwsgi;
    scgi_temp_path /home/user/app/nginx/temp/scgi;
    access_log /home/user/app/nginx/logs/access.log;
    server {
        listen 8080;
        location / {
            return 200 "OK\n";
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/operator/Cargo.toml
[package]
name = "operator"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_yaml = "0.9"
EOF

    cat << 'EOF' > /home/user/app/operator/src/main.rs
use serde::Deserialize;
use std::env;
use std::fs;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Deserialize)]
struct Manifest {
    routes: Vec<Route>,
}

#[derive(Deserialize)]
struct Route {
    path: String,
    port: u16,
}

fn main() {
    // Agent must read env vars here
    let manifest_path = String::new();
    let nginx_conf_path = String::new();
    let backup_dir = String::new();

    let manifest_content = fs::read_to_string(&manifest_path).unwrap_or_default();
    // let manifest: Manifest = serde_yaml::from_str(&manifest_content).unwrap();

    // Agent must implement backup here

    // Agent must generate Nginx config
    let mut config = String::new();
    config.push_str("events {}\nhttp {\n  server {\n    listen 8080;\n");

    // ...

    config.push_str("  }\n}\n");

    // fs::write(&nginx_conf_path, config).unwrap();

    /*
    Command::new("nginx")
        .args(["-c", &nginx_conf_path, "-s", "reload"])
        .status()
        .unwrap();
    */
}
EOF

    # Pre-fetch crates to speed up agent runs and avoid timeout issues
    cd /home/user/app/operator
    cargo fetch || true
    cd /

    chown -R user:user /home/user
    chmod -R 777 /home/user
