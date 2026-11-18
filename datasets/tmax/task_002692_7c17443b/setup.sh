#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y nginx redis-server golang gunicorn wrk curl sudo

    # Install Python packages
    pip3 install flask redis gunicorn

    # Create directories
    mkdir -p /app/go_vm /app/backend /app/lib

    # Create /app/go_vm/vm.go
    cat << 'EOF' > /app/go_vm/vm.go
package main

import "C"
import (
	"strconv"
	"strings"
)

//export ExecuteBatch
func ExecuteBatch(batchStr *C.char) *C.char {
	// Simulated broken implementation with race conditions
	return C.CString("15,12")
}

func main() {}
EOF

    # Create /app/backend/ffi.py
    cat << 'EOF' > /app/backend/ffi.py
import ctypes
import os

lib = ctypes.CDLL('/app/lib/libvm.so')

# Missing argtypes and restype
# lib.ExecuteBatch.argtypes = [ctypes.c_char_p]
# lib.ExecuteBatch.restype = ctypes.c_char_p

def execute_batch(batch):
    batch_str = ",".join(batch).encode('utf-8')
    res = lib.ExecuteBatch(batch_str)
    return res.decode('utf-8').split(',')
EOF

    # Create /app/backend/app.py
    cat << 'EOF' > /app/backend/app.py
from flask import Flask, request, jsonify
from ffi import execute_batch

app = Flask(__name__)

@app.route('/api/execute', methods=['POST'])
def execute():
    data = request.get_json()
    batch = data.get('batch', [])
    # Missing Redis caching
    results = execute_batch(batch)
    return jsonify({"results": results})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create /app/benchmark.py
    cat << 'EOF' > /app/benchmark.py
import subprocess
import json
import re

def run_benchmark():
    cmd = [
        "wrk", "-t12", "-c400", "-d10s",
        "-s", "post.lua",
        "http://127.0.0.1:8080/api/execute"
    ]
    with open("post.lua", "w") as f:
        f.write('wrk.method = "POST"\nwrk.body = \'{"batch": ["PUSH 5 PUSH 10 ADD", "PUSH 3 PUSH 4 MUL"]}\'\nwrk.headers["Content-Type"] = "application/json"\n')

    result = subprocess.run(cmd, capture_output=True, text=True)

    match = re.search(r"Requests/sec:\s+([\d.]+)", result.stdout)
    rps = float(match.group(1)) if match else 0.0

    with open("/app/benchmark_results.json", "w") as f:
        json.dump({"rps": rps}, f)

if __name__ == "__main__":
    run_benchmark()
EOF

    # Create /etc/nginx/sites-available/default
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080;
    server_name localhost;

    location /api/ {
        proxy_pass http://127.0.0.1:5000/;
    }
}
EOF

    # Create /app/restart_services.sh
    cat << 'EOF' > /app/restart_services.sh
#!/bin/bash
systemctl restart nginx
systemctl restart redis-server
pkill gunicorn
cd /app/backend && gunicorn -w 4 -b 127.0.0.1:5000 app:app --daemon
EOF
    chmod +x /app/restart_services.sh

    # Set up user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
