#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip squashfuse squashfs-tools golang docker.io docker-compose curl openssh-client
    pip3 install pytest requests

    mkdir -p /app/restore-env/nginx
    mkdir -p /app/restore-env/go-app
    mkdir -p /app/data

    cat << 'EOF' > /app/restore-env/docker-compose.yml
version: '3.8'
services:
  nginx:
    image: nginx:latest
    ports:
      - "8080:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - shared-socket:/var/run/go-app
    depends_on:
      - go-app

  go-app:
    build: ./go-app
    volumes:
      - /app/data:/app/data:ro
      - shared-socket:/var/run/go-app
    expose:
      - "9090"

  ssh-bastion:
    image: lscr.io/linuxserver/openssh-server:latest
    environment:
      - USER_NAME=admin
      - USER_PASSWORD=adminpass
      - PASSWORD_ACCESS=true
    ports:
      - "2222:2222"

volumes:
  shared-socket:
EOF

    cat << 'EOF' > /app/restore-env/nginx/nginx.conf
events {}
http {
    server {
        listen 80;
        location / {
            proxy_pass http://unix:/var/run/go-app/app.sock;
        }
    }
}
EOF

    cat << 'EOF' > /app/restore-env/go-app/Dockerfile
FROM golang:1.20
WORKDIR /app
COPY main.go .
RUN go build -o main main.go
CMD ["./main"]
EOF

    cat << 'EOF' > /app/restore-env/go-app/main.go
package main

import (
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"
)

func main() {
	go func() {
		http.ListenAndServe(":9090", nil)
	}()

	http.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		content, err := os.ReadFile("/app/data/access.log")
		if err != nil {
			http.Error(w, "File not found", 404)
			return
		}
		lines := strings.Split(string(content), "\n")
		count := 0
		for _, line := range lines {
			matched, _ := regexp.MatchString(`GET /api/v1/data`, line)
			if matched {
				count++
			}
			time.Sleep(1 * time.Microsecond)
		}
		fmt.Fprintf(w, `{"count": %d}`, count)
	})

	fmt.Println("Starting server on :8081")
	http.ListenAndServe(":8081", nil)
}
EOF

    mkdir -p /tmp/backup
    for i in $(seq 1 10000); do
        echo "127.0.0.1 - - [10/Oct/2023:13:55:36 -0700] \"GET /api/v1/data HTTP/1.1\" 200 2326" >> /tmp/backup/access.log
    done
    mksquashfs /tmp/backup /app/backup.sqsh
    rm -rf /tmp/backup

    touch /app/restore-env/fstab
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
