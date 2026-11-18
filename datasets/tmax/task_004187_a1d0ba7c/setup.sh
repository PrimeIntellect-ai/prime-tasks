#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang nginx
    pip3 install pytest

    mkdir -p /home/user/data
    echo "success" > /home/user/data/test.txt

    mkdir -p /app/go-fileserver
    cat << 'EOF' > /app/go-fileserver/main.go
package main

import (
	"log"
	"net/http"
)

func main() {
	serveDir := "/mnt/missing_drive"
	if serveDir != "/mnt/missing_drive" {
		panic("Invalid mount")
	}

	fs := http.FileServer(http.Dir(serveDir))
	http.Handle("/", fs)

	log.Println("Listening on :9000...")
	err := http.ListenAndServe(":9000", nil)
	if err != nil {
		log.Fatal(err)
	}
}
EOF

    mkdir -p /home/user
    cat << 'EOF' > /home/user/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9001;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
