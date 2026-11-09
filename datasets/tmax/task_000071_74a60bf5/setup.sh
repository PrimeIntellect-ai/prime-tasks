#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ golang nginx
pip3 install pytest flask requests --default-timeout=100

mkdir -p /app/src/cpp /app/src/go /app/src/python /app/corpora /app/nginx

cat << 'EOF' > /app/corpora/clean.txt
2 + 2
3.14 * x ^ 2
(pi / 2) + e
x * y - 1
123.456 / 789
EOF

cat << 'EOF' > /app/corpora/evil.txt
__import__('os').system('echo pwned')
eval("1+1")
open('/etc/passwd').read()
(lambda: 1)()
10**1000000000
EOF

cat << 'EOF' > /app/src/cpp/engine.cpp
#include <cstdlib>

int main() {
    // Start a mock HTTP server using python to avoid external C++ dependencies
    system("python3 -c \"from http.server import BaseHTTPRequestHandler, HTTPServer; import urllib.parse; class Handler(BaseHTTPRequestHandler):\\n"
           " def do_GET(self):\\n"
           "  qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)\\n"
           "  expr = qs.get('expr', [''])[0]\\n"
           "  self.send_response(200)\\n"
           "  self.end_headers()\\n"
           "  self.wfile.write(('C++: ' + expr).encode())\\n"
           "HTTPServer(('127.0.0.1', 8082), Handler).serve_forever()\"");
    return 0;
}
EOF

cat << 'EOF' > /app/src/go/engine.go
package main

import (
	"fmt"
	"net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
	expr := r.URL.Query().Get("expr")
	fmt.Fprintf(w, "Go: %s", expr)
}

func main() {
	http.HandleFunc("/eval", handler)
	http.ListenAndServe("127.0.0.1:8081", nil)
}
EOF

cat << 'EOF' > /app/src/python/app.py
from flask import Flask, request, abort
import requests

app = Flask(__name__)

@app.route('/evaluate')
def evaluate():
    expr = request.args.get('expr', '')
    # TODO: Implement is_safe_math check
    # TODO: Implement routing logic
    return "Not Implemented", 501

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
