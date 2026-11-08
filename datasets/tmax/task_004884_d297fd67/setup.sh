#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl
    pip3 install pytest requests

    mkdir -p /app/proxy /app/waf /app/backend /app/corpus/clean /app/corpus/evil

    # Create proxy
    cat << 'EOF' > /app/proxy/main.go
package main

import (
	"bytes"
	"io"
	"log"
	"net/http"
)

func handleRequestAndRedirect(res http.ResponseWriter, req *http.Request) {
	body, _ := io.ReadAll(req.Body)
	req.Body = io.NopCloser(bytes.NewBuffer(body))

	wafReq, _ := http.NewRequest("POST", "http://localhost:5000/", bytes.NewBuffer(body))
	wafReq.Header = req.Header
	client := &http.Client{}
	wafResp, err := client.Do(wafReq)
	if err != nil || wafResp.StatusCode != 200 {
		res.WriteHeader(http.StatusForbidden)
		return
	}

	backendReq, _ := http.NewRequest(req.Method, "http://localhost:9000/", bytes.NewBuffer(body))
	backendReq.Header = req.Header
	backendResp, err := client.Do(backendReq)
	if err != nil {
		res.WriteHeader(http.StatusInternalServerError)
		return
	}
	defer backendResp.Body.Close()

	res.WriteHeader(backendResp.StatusCode)
	io.Copy(res, backendResp.Body)
}

func main() {
	http.HandleFunc("/", handleRequestAndRedirect)
	log.Fatal(http.ListenAndServe(":8000", nil))
}
EOF

    # Create WAF
    cat << 'EOF' > /app/waf/waf.py
import BaseHTTPServer
import json
import base64
import re

class WAFHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)

        try:
            data = json.loads(post_data)
            payload = base64.b64decode(data.get('payload', '')).encode('hex')
            if re.search(r'script|union|select', payload, re.IGNORECASE):
                self.send_response(403)
                self.end_headers()
                return
        except Exception:
            pass

        self.send_response(200)
        self.end_headers()

def run(server_class=BaseHTTPServer.HTTPServer, handler_class=WAFHandler, port=5000):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    httpd.serve_forever()

if __name__ == "__main__":
    run()
EOF

    # Create backend
    cat << 'EOF' > /app/backend/server.py
import http.server
import json

class BackendHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"status": "success", "data": "processed"}).encode())

    def do_GET(self):
        self.do_POST()

def run(server_class=http.server.HTTPServer, handler_class=BackendHandler, port=9000):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    httpd.serve_forever()

if __name__ == "__main__":
    run()
EOF

    # Create corpus files
    for i in $(seq 1 10); do
        echo '{"payload": "Y2xlYW4="}' > /app/corpus/clean/clean_$i.json
        echo '{"payload": "PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg=="}' > /app/corpus/evil/evil_$i.json
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
