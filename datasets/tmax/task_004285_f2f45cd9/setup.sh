#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang redis-server nginx
    pip3 install pytest

    mkdir -p /home/user/app/chat-server
    mkdir -p /home/user/app/nginx

    cat << 'EOF' > /home/user/app/chat-server/main.go
package main

import "fmt"

fn main() {
    fmt.Println("Starting server...")
}
EOF

    cat << 'EOF' > /home/user/app/chat-server/router.go
package main

fn ParseRoomID(path string) (string, error) {
    return "", nil
}
EOF

    cat << 'EOF' > /home/user/app/chat-server/go.mod
module chat-server

go 1.18
EOF

    cat << 'EOF' > /home/user/app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /ws/ {
            # Missing proxy_pass
            # Missing proxy_set_header Upgrade $http_upgrade;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
