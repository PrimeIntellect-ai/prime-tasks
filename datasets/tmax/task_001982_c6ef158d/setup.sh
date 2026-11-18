#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    # Create the oracle mutator
    cat << 'EOF' > /app/oracle_mutator.go
package main

import (
	"encoding/json"
	"io/ioutil"
	"os"
	"strings"
)

func main() {
	input, err := ioutil.ReadAll(os.Stdin)
	if err != nil {
		return
	}
	var data map[string]interface{}
	if err := json.Unmarshal(input, &data); err != nil {
		os.Stdout.Write(input)
		return
	}

	if kind, ok := data["kind"].(string); ok && kind == "Pod" {
		if spec, ok := data["spec"].(map[string]interface{}); ok {
			if containers, ok := spec["containers"].([]interface{}); ok {
				for _, c := range containers {
					if cMap, ok := c.(map[string]interface{}); ok {
						if img, ok := cMap["image"].(string); ok {
							if strings.HasSuffix(img, ":latest") {
								cMap["image"] = strings.TrimSuffix(img, ":latest") + ":staged"
							}
						}
					}
				}
				newContainer := map[string]interface{}{
					"name":  "qemu-vnc",
					"image": "localhost:5000/qemu-vnc:1.0",
				}
				spec["containers"] = append(containers, newContainer)
			}
		}
	}

	output, _ := json.Marshal(data)
	os.Stdout.Write(output)
}
EOF
    cd /app && go build -o oracle_mutator oracle_mutator.go

    # Create dummy services for the test
    cat << 'EOF' > /app/deployer_daemon.py
import http.server
import socketserver
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
with socketserver.TCPServer(("127.0.0.1", 8080), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /app/registry.py
import http.server
import socketserver
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
with socketserver.TCPServer(("127.0.0.1", 5000), Handler) as httpd:
    httpd.serve_forever()
EOF

    # Create environment file
    echo 'FILTER_CMD=""' > /home/user/deployer.env

    chmod -R 777 /home/user
    chmod -R 777 /app
