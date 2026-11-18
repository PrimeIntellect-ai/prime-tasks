#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl
    pip3 install pytest

    mkdir -p /home/user/migration_test
    cd /home/user/migration_test

    cat << 'EOF' > legacy_service.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from urllib.parse import urlparse, parse_qs

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        qs = parse_qs(urlparse(self.path).query)
        user_id = qs.get('id', [''])[0]

        # Legacy response (snake_case)
        resp = {
            "user_id": int(user_id) if user_id.isdigit() else 0,
            "first_name": "Alice",
            "last_login": "2023-01-01"
        }
        self.wfile.write(json.dumps(resp).encode('utf-8'))

HTTPServer(('127.0.0.1', 8022), Handler).serve_forever()
EOF

    cat << 'EOF' > new_service.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from urllib.parse import urlparse, parse_qs

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        qs = parse_qs(urlparse(self.path).query)
        user_id = qs.get('id', [''])[0]

        # New response (camelCase)
        # BUG in new service: ID 555 returns slightly different name to trigger a diff
        resp = {
            "userId": int(user_id) if user_id.isdigit() else 0,
            "firstName": "Alice" if user_id != "555" else "Alice_New",
            "lastLogin": "2023-01-01"
        }
        self.wfile.write(json.dumps(resp).encode('utf-8'))

HTTPServer(('127.0.0.1', 8033), Handler).serve_forever()
EOF

    cat << 'EOF' > proxy.go
package main

import (
	"fmt"
	"net/http"
	_ "net/http/pprof"
)

var GlobalLeakTracker [][]byte

func handler(w http.ResponseWriter, r *http.Request) {
    // Memory leak
    dummyData := make([]byte, 1024*1024)
    GlobalLeakTracker = append(GlobalLeakTracker, dummyData)

    // TODO: Forward requests to :8022 and :8033 with parameters
    // TODO: Read JSON, convert snake_case to camelCase for 8022
    // TODO: Diff responses and write to /home/user/migration_test/diff_results.log

    fmt.Fprintln(w, "OK")
}

func main() {
	http.HandleFunc("/api/user", handler)
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > run_requests.sh
#!/bin/bash
curl -s "http://localhost:8080/api/user?id=123" > /dev/null
curl -s "http://localhost:8080/api/user?id=555" > /dev/null
EOF
    chmod +x run_requests.sh

    go mod init migration_test
    go get github.com/sergi/go-diff/diffmatchpatch || true

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
