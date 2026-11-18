#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nginx cargo
    pip3 install pytest

    mkdir -p /home/user/restore/app/src
    mkdir -p /home/user/restore/tmp
    mkdir -p /home/user/restore/var/run
    mkdir -p /home/user/nginx_tmp_client
    mkdir -p /home/user/nginx_tmp_proxy
    mkdir -p /home/user/nginx_tmp_fastcgi
    mkdir -p /home/user/nginx_tmp_uwsgi
    mkdir -p /home/user/nginx_tmp_scgi

    cat << 'EOF' > /home/user/restore/app/Cargo.toml
[package]
name = "mailgate"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/restore/app/src/main.rs
use std::io::{Read, Write};
use std::os::unix::net::UnixListener;
use std::fs;

fn main() {
    let socket_path = "/home/user/restore/tmp/mailgate.sock";
    let _ = fs::remove_file(socket_path);
    let listener = UnixListener::bind(socket_path).unwrap();

    for stream in listener.incoming() {
        match stream {
            Ok(mut stream) => {
                let mut buf = [0; 1024];
                let _ = stream.read(&mut buf);
                let response = "HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nMAILGATE_RESTORE_V1_OK\n";
                let _ = stream.write_all(response.as_bytes());
            }
            Err(_) => continue,
        }
    }
}
EOF

    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/nginx_error.log;
pid /home/user/nginx.pid;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx_tmp_client;
    proxy_temp_path /home/user/nginx_tmp_proxy;
    fastcgi_temp_path /home/user/nginx_tmp_fastcgi;
    uwsgi_temp_path /home/user/nginx_tmp_uwsgi;
    scgi_temp_path /home/user/nginx_tmp_scgi;
    access_log /home/user/nginx_access.log;

    server {
        listen 8080;

        location /health {
            proxy_pass http://unix:/home/user/restore/var/run/mailgate.sock;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/restore
    chown -R user:user /home/user/nginx*
    chmod -R 777 /home/user
