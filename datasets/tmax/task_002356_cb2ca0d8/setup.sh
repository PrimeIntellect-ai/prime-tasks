#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang redis-server nginx curl
    pip3 install pytest flask

    mkdir -p /home/user/app/nginx /home/user/app/flask /home/user/app/go-auth /home/user/corpus/clean /home/user/corpus/evil

    # Nginx config skeleton
    cat << 'EOF' > /home/user/app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;

        location /api/ {
            # TODO: Proxy to Flask
        }

        location /auth/ {
            # TODO: Proxy to Go auth
        }
    }
}
EOF

    # Flask App
    cat << 'EOF' > /home/user/app/flask/app.py
from flask import Flask
app = Flask(__name__)
@app.route('/api/ping')
def ping(): return "pong"
if __name__ == '__main__': app.run(port=8081)
EOF

    # Go App
    cat << 'EOF' > /home/user/app/go-auth/main.go
package main
import (
    "fmt"
    "net/http"
)
func main() {
    http.HandleFunc("/auth/login", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "authenticated")
    })
    http.ListenAndServe(":8082", nil)
}
EOF
    cd /home/user/app/go-auth && go mod init auth && go mod tidy

    # Generate Corpus
    # Clean 1
    cat << 'EOF' > /home/user/corpus/clean/req1.txt
GET /api/data HTTP/1.1
Host: localhost
X-API-Version: 1.5.0
EOF

    # Clean 2
    cat << 'EOF' > /home/user/corpus/clean/req2.txt
POST /api/upload HTTP/1.1
Host: localhost
X-API-Version: 2.0.1
EOF

    # Evil 1 (Bad Semver)
    cat << 'EOF' > /home/user/corpus/evil/req1.txt
GET /api/data HTTP/1.1
Host: localhost
X-API-Version: 1.4.9
EOF

    # Evil 2 (Missing Semver)
    cat << 'EOF' > /home/user/corpus/evil/req2.txt
GET /api/data HTTP/1.1
Host: localhost
EOF

    # Evil 3 (Path traversal)
    cat << 'EOF' > /home/user/corpus/evil/req3.txt
GET /api/../etc/passwd HTTP/1.1
Host: localhost
X-API-Version: 2.0.0
EOF

    # Evil 4 (Path traversal encoded)
    cat << 'EOF' > /home/user/corpus/evil/req4.txt
GET /api/%2e%2e%2fetc/passwd HTTP/1.1
Host: localhost
X-API-Version: 2.0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
