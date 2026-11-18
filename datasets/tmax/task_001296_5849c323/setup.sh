#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/auditing_workspace/www
mkdir -p /home/user/auditing_workspace/web_server/src

echo "<html><body>Hello</body></html>" > /home/user/auditing_workspace/www/index.html
echo "console.log('test');" > /home/user/auditing_workspace/www/script.js
echo "body { color: red; }" > /home/user/auditing_workspace/www/style.css

cat << 'EOF' > /home/user/auditing_workspace/web_server/Cargo.toml
[package]
name = "web_server"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /home/user/auditing_workspace/web_server/src/main.rs
use std::io::Write;
use std::net::TcpListener;

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<html><body>Safe!</body></html>";
        stream.write_all(response.as_bytes()).unwrap();
    }
}
EOF

cat << 'EOF' > /home/user/auditing_workspace/sshd_config_custom
Port 2222
PermitRootLogin yes
PasswordAuthentication yes
X11Forwarding no
EOF

chown -R user:user /home/user/auditing_workspace

chmod -R 777 /home/user
chmod 644 /home/user/auditing_workspace/www/index.html
chmod 777 /home/user/auditing_workspace/www/script.js
chmod 666 /home/user/auditing_workspace/www/style.css
