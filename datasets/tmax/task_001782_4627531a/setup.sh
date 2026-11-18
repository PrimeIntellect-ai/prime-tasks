#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libssl-dev g++ curl binutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # 1. Create the wordlist
    cat << 'EOF' > /home/user/wordlist.txt
apple123
qwerty
password
letmein1
bluebird99
sunshine
admin123
compliance2023
securepass
EOF

    # 2. Compile the dummy legacy_auth.bin for ELF analysis
    cat << 'EOF' > /home/user/dummy_auth.cpp
#include <iostream>
#include <string>

// The hardcoded 16-character salt
const char* GLOBAL_SALT = "S4lTy_B3v3r4g3!!";

int main() {
    std::string user_input;
    std::cin >> user_input;
    if (user_input == GLOBAL_SALT) {
        std::cout << "Match" << std::endl;
    }
    return 0;
}
EOF
    g++ -O2 /home/user/dummy_auth.cpp -o /home/user/legacy_auth.bin
    rm /home/user/dummy_auth.cpp

    # 3. Create the database
    cat << 'EOF' > /home/user/db.txt
user1:a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3
compliance_admin:3f52a78107cd922f36bc9625d3ccdb8558eb8980b18ccf71e549cba91605e5d3
guest:0ffe1abd1a08215353c233d6e009613e95eec4253832a761af28ff37ac5a150c
EOF

    # 4. Create the Python web server mocking the legacy auth service
    cat << 'EOF' > /home/user/server.py
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class AuthHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/login':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data)
                if data.get('username') == 'compliance_admin' and data.get('password') == 'bluebird99':
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(b'{"status":"success","token":"AUTH_TOKEN_9932"}')
                else:
                    self.send_response(401)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(b'{"status":"error","message":"Invalid credentials"}')
            except Exception:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b'Bad Request')
        else:
            self.send_response(404)
            self.end_headers()

    # Suppress logging
    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9090), AuthHandler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
