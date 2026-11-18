#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/gateway-pr

    cat << 'EOF' > /home/user/gateway-pr/routes.json
{
  "version": "1.0",
  "routes": [
    {
      "path": "/api/v1/users",
      "target_service": "user-service-backend"
    },
    {
      "path": "/api/v1/orders",
      "target_service": "order-service-backend"
    }
  ]
}
EOF

    cat << 'EOF' > /home/user/gateway-pr/legacy_gateway.py
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

with open('routes.json') as f:
    config = json.load(f)
    routes = {r['path']: r['target_service'] for r in config['routes']}

clients = {}

class GatewayHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        client_ip = self.client_address[0]
        now = time.time()

        if client_ip not in clients:
            clients[client_ip] = []

        # keep only timestamps from the last 1 second
        clients[client_ip] = [t for t in clients[client_ip] if now - t < 1.0]

        if len(clients[client_ip]) >= 5:
            self.send_response(429)
            self.end_headers()
            self.wfile.write(b"Too Many Requests")
            return

        clients[client_ip].append(now)

        if self.path not in routes:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")
            return

        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"Routed to {routes[self.path]}".encode())

if __name__ == "__main__":
    server = HTTPServer(('localhost', 8080), GatewayHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/gateway-pr/main.go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"
)

type Config struct {
	Routes []string `json:"routes"` // BUG: Incorrect struct for parsing
}

var rateLimits = make(map[string][]time.Time) // BUG: No concurrency protection

var routesMap = make(map[string]string)

func main() {
	data, _ := os.ReadFile("routes.json")
	var config Config
	json.Unmarshal(data, &config)

	// Broken parsing logic
	for _, r := range config.Routes {
		routesMap[r] = "unknown-service"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		ip := r.RemoteAddr
		now := time.Now()

		// Race condition here
		history := rateLimits[ip]
		var valid []time.Time
		for _, t := range history {
			if now.Sub(t) < time.Second {
				valid = append(valid, t)
			}
		}

		if len(valid) >= 5 {
			http.Error(w, "Too Many Requests", http.StatusTooManyRequests)
			return
		}
		valid = append(valid, now)
		rateLimits[ip] = valid

		// Bug: always returns 200, ignores 404 requirement
		fmt.Fprintf(w, "Routed to %s", routesMap[r.URL.Path])
	})

	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/gateway-pr/bench.sh
#!/bin/bash
echo "Starting benchmark..."
for i in {1..20}; do
    curl -s http://127.0.0.1:8080/api/v1/users &
done
wait
echo "Benchmark finished."
EOF

    chmod +x /home/user/gateway-pr/bench.sh

    chown -R user:user /home/user/gateway-pr
    chmod -R 777 /home/user
