#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ rustc nodejs
pip3 install pytest requests

useradd -m -s /bin/bash user || true

mkdir -p /home/user/workspace/src

cat << 'EOF' > /home/user/workspace/src/main.cpp
#include <iostream>
int main() { std::cout << "C++ Artifact" << std::endl; return 0; }
EOF

cat << 'EOF' > /home/user/workspace/src/main.rs
fn main() { println!("Rust Artifact"); }
EOF

cat << 'EOF' > /home/user/workspace/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import time

request_times = []

class ArtifactHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        global request_times
        if self.path == '/upload':
            now = time.time()
            # Clean old requests
            request_times = [t for t in request_times if now - t < 1.0]

            if len(request_times) >= 2:
                self.send_response(429)
                self.end_headers()
                self.wfile.write(b"Too Many Requests")
                return

            request_times.append(now)

            artifact_type = self.headers.get('X-Artifact-Type')
            if artifact_type not in ['cpp', 'rust']:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Bad Request: Invalid or missing X-Artifact-Type")
                return

            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), ArtifactHandler)
    server.serve_forever()
EOF

cat << 'EOF' > /home/user/workspace/legacy_tester.js
const { execSync } = require('child_process');
const http = require('http');
const fs = require('fs');

// 1. Build
fs.mkdirSync('artifacts', { recursive: true });
execSync('g++ src/main.cpp -o artifacts/cpp_artifact');
execSync('rustc src/main.rs -o artifacts/rust_artifact');

// 2 & 3 & 4. Testing logic would be here, but we're translating it.
console.log("Translation target: test validation (400) and rate limits (429)");
EOF

chown -R user:user /home/user/workspace
chmod -R 777 /home/user
