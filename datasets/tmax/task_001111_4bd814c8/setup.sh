#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go redis-server nginx curl
    pip3 install pytest redis

    mkdir -p /app/nginx
    mkdir -p /app/src

    # Create populate_redis.py
    cat << 'EOF' > /app/populate_redis.py
import redis
r = redis.Redis(host='localhost', port=6379)
if r.llen('dataset') == 0:
    for i in range(100):
        r.rpush('dataset', str(1.0 + i*0.05))
EOF

    # Create api_server
    cat << 'EOF' > /app/api_server
#!/usr/bin/env python3
import os
import redis
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/dataset':
            port = int(os.environ.get('REDIS_PORT', 6379))
            try:
                r = redis.Redis(host='localhost', port=port)
                data = r.lrange('dataset', 0, -1)
                self.send_response(200)
                self.end_headers()
                for d in data:
                    self.wfile.write(d + b'\n')
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())

if __name__ == '__main__':
    server = HTTPServer(('localhost', 9000), RequestHandler)
    server.serve_forever()
EOF
    chmod +x /app/api_server

    # Create nginx.conf
    cat << 'EOF' > /app/nginx/nginx.conf
pid /tmp/nginx.pid;
events {}
http {
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    error_log /tmp/error.log;
    access_log /tmp/access.log;
    server {
        listen 8080;
        location / {
            proxy_pass http://localhost:9001;
        }
    }
}
EOF

    # Create start_services.sh
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
export REDIS_PORT=6380
redis-server --port 6379 --daemonize yes
sleep 1
python3 /app/populate_redis.py
/app/api_server &
nginx -c /app/nginx/nginx.conf
EOF
    chmod +x /app/start_services.sh

    # Create oracle bootstrapper
    cat << 'EOF' > /app/src/oracle.go
package main

import (
	"fmt"
	"math/rand"
	"os"
	"sort"
	"strconv"
	"strings"
	"io/ioutil"
)

func main() {
	seed, _ := strconv.ParseInt(os.Args[1], 10, 64)
	B, _ := strconv.Atoi(os.Args[2])

	data, err := ioutil.ReadFile("/home/user/dataset.txt")
	if err != nil {
		panic(err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	var D []float64
	for _, l := range lines {
		if l == "" {
			continue
		}
		f, _ := strconv.ParseFloat(l, 64)
		D = append(D, f)
	}
	N := len(D)

	rng := rand.New(rand.NewSource(seed))
	means := make([]float64, B)
	for b := 0; b < B; b++ {
		sum := 0.0
		for i := 0; i < N; i++ {
			idx := rng.Intn(N)
			sum += D[idx]
		}
		means[b] = sum / float64(N)
	}
	sort.Float64s(means)
	lower := means[int(0.025*float64(B))]
	upper := means[int(0.975*float64(B))]
	fmt.Printf("CI: [%.4f, %.4f]\n", lower, upper)
}
EOF
    cd /app/src && go build -o /app/oracle_bootstrapper oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
