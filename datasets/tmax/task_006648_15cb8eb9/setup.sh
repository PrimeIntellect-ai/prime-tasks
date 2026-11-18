#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

mkdir -p /home/user/mobile_build

# 1. Create api.py
cat << 'EOF' > /home/user/mobile_build/api.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class BuildAPI(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/constraints':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            constraints = {
                "variables": {
                    "ARCH": ["arm32", "arm64", "x86"],
                    "OPT": ["O1", "O2", "O3"],
                    "LTO": ["true", "false"]
                },
                "rules": [
                    {"if": {"ARCH": "x86"}, "then": {"LTO": "false"}},
                    {"if": {"OPT": "O3"}, "then": {"LTO": "true"}},
                    {"if": {"ARCH": "arm32"}, "then": {"OPT": ["O1", "O2"]}},
                    {"if": {"LTO": "true"}, "then": {"ARCH": "arm64"}},
                    {"if": {"OPT": "O2"}, "then": {"LTO": "false"}}
                ]
            }
            self.wfile.write(json.dumps(constraints).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/report':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            payload = json.loads(post_data.decode())

            # Verify the solution
            expected = {"ARCH": "arm64", "OPT": "O3", "LTO": "true"}
            if payload == expected:
                with open('/home/user/mobile_build/success.log', 'w') as f:
                    f.write("SUCCESS")
                self.send_response(200)
            else:
                self.send_response(400)
            self.end_headers()

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8080)
    httpd = HTTPServer(server_address, BuildAPI)
    httpd.serve_forever()
EOF

# 2. Create orchestrator.py (with memory leak)
cat << 'EOF' > /home/user/mobile_build/orchestrator.py
import urllib.request
import json
import itertools

def fetch_constraints():
    req = urllib.request.urlopen('http://127.0.0.1:8080/constraints')
    return json.loads(req.read().decode())

def validate(assignment, rules):
    for rule in rules:
        cond = rule['if']
        conseq = rule['then']

        # Check if condition is met
        cond_met = True
        for k, v in cond.items():
            if assignment.get(k) != v:
                cond_met = False
                break

        if cond_met:
            for k, v in conseq.items():
                if isinstance(v, list):
                    if assignment.get(k) not in v: return False
                else:
                    if assignment.get(k) != v: return False
    return True

def solve():
    data = fetch_constraints()
    vars = data['variables']
    rules = data['rules']

    keys = list(vars.keys())
    values = list(vars.values())

    leak_list = []

    for combo in itertools.product(*values):
        assignment = dict(zip(keys, combo))
        # MEMORY LEAK: Storing a 10MB string for every state evaluated
        leak_list.append(" " * (10 * 1024 * 1024))
        if validate(assignment, rules):
            with open('/home/user/mobile_build/build.env', 'w') as f:
                for k, v in assignment.items():
                    f.write(f"{k}={v}\n")
            return assignment

if __name__ == '__main__':
    solve()
EOF

# 3. Create native.cpp
cat << 'EOF' > /home/user/mobile_build/native.cpp
#include <iostream>
int main() {
    std::cout << "Mobile Native Library" << std::endl;
    return 0;
}
EOF

# 4. Create Makefile
cat << 'EOF' > /home/user/mobile_build/Makefile
include build.env

libmobile.so: native.cpp
	g++ -shared -fPIC native.cpp -o libmobile.so -DARCH=$(ARCH) -DOPT=$(OPT)

EOF

# Ensure permissions
chmod +x /home/user/mobile_build/api.py
chmod +x /home/user/mobile_build/orchestrator.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
