#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx rustc psmisc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/nginx/access.log;
    error_log /home/user/nginx/error.log;
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

    mkdir -p /home/user/app/target/release
    cat << 'EOF' > /home/user/app/server.rs
use std::io::{Read, Write};
use std::net::TcpListener;
use std::env;
use std::thread;

fn main() {
    let port = env::var("PORT").unwrap_or_else(|_| "9999".to_string());
    let addr = format!("127.0.0.1:{}", port);
    let listener = TcpListener::bind(&addr).unwrap();

    for stream in listener.incoming() {
        match stream {
            Ok(mut stream) => {
                thread::spawn(move || {
                    let mut buffer = [0; 1024];
                    if let Ok(_) = stream.read(&mut buffer) {
                        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}";
                        stream.write_all(response.as_bytes()).unwrap();
                        stream.flush().unwrap();
                    }
                });
            }
            Err(_) => {}
        }
    }
}
EOF
    rustc /home/user/app/server.rs -o /home/user/app/target/release/server
    rm /home/user/app/server.rs

    cat << 'EOF' > /home/user/app/.env
PORT=8081
EOF

    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
cd /tmp && /home/user/app/target/release/server &
EOF
    chmod +x /home/user/app/start.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
