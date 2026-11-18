#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nginx \
        docker.io \
        docker-compose \
        systemd \
        golang-go

    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create required directories
    mkdir -p /home/user/backend
    mkdir -p /home/user/proxy
    mkdir -p /home/user/.config/systemd/user
    mkdir -p /app

    # 1. Create docker-compose.yml
    cat << 'EOF' > /home/user/backend/docker-compose.yml
version: '3'
services:
  app1:
    image: traefik/whoami
    expose:
      - "80"
  app2:
    image: traefik/whoami
    expose:
      - "80"
  app3:
    image: traefik/whoami
    expose:
      - "80"
EOF

    # 2. Create nginx.conf (with intentional syntax error)
    cat << 'EOF' > /home/user/proxy/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    upstream backend {
        server 127.0.0.1:8001;
        server 127.0.0.1:8002
        server 127.0.0.1:8003;
    }
    server {
        listen 8080;
        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

    # 3. Create systemd service (with intentional incorrect Type)
    cat << 'EOF' > /home/user/.config/systemd/user/local-proxy.service
[Unit]
Description=Local Nginx Proxy

[Service]
Type=simple
ExecStart=/usr/sbin/nginx -c /home/user/proxy/nginx.conf
ExecReload=/bin/kill -s HUP $MAINPID
Restart=on-failure

[Install]
WantedBy=default.target
EOF

    # 4. Build the lb_bench binary
    cat << 'EOF' > /tmp/lb_bench.go
package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"sync"
	"time"
)

type Result struct {
	RPS            float64 `json:"rps"`
	UniqueBackends int     `json:"unique_backends"`
	Errors         int     `json:"errors"`
}

func main() {
	start := time.Now()
	var wg sync.WaitGroup
	reqCount := 1000

	backends := make(map[string]bool)
	var mu sync.Mutex
	errors := 0

	client := &http.Client{Timeout: 2 * time.Second}

	for i := 0; i < reqCount; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			resp, err := client.Get("http://127.0.0.1:8080/")
			if err != nil {
				mu.Lock()
				errors++
				mu.Unlock()
				return
			}
			defer resp.Body.Close()
			if resp.StatusCode != 200 {
				mu.Lock()
				errors++
				mu.Unlock()
				return
			}
			body, _ := ioutil.ReadAll(resp.Body)
			mu.Lock()
			backends[string(body)] = true
			mu.Unlock()
		}()
	}
	wg.Wait()
	duration := time.Since(start).Seconds()
	rps := float64(reqCount) / duration

	res := Result{
		RPS:            rps,
		UniqueBackends: len(backends),
		Errors:         errors,
	}
	out, _ := json.Marshal(res)
	fmt.Println(string(out))
}
EOF

    cd /tmp
    go build -o /app/lb_bench lb_bench.go
    chmod +x /app/lb_bench
    rm /tmp/lb_bench.go

    # Final permissions
    chmod -R 777 /home/user
