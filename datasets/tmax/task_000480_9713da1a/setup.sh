#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev redis-server nginx curl
    pip3 install pytest flask redis gunicorn

    mkdir -p /home/user/app/c_src

    cat << 'EOF' > /home/user/app/reference.py
#!/usr/bin/env python3
import sys
import json
import math

def compute_and_merge_ref(n, m):
    arr1 = [math.sin(i) * 100.0 for i in range(n)]
    arr2 = [math.cos(j) * 100.0 for j in range(m)]
    merged = sorted(arr1 + arr2)
    return merged[-10:] # Return top 10

if __name__ == "__main__":
    if len(sys.argv) == 3:
        n = int(sys.argv[1])
        m = int(sys.argv[2])
        res = compute_and_merge_ref(n, m)
        print(json.dumps(res, separators=(',', ':')))
EOF
    chmod +x /home/user/app/reference.py

    cat << 'EOF' > /home/user/app/c_src/poly.c
#include <stdlib.h>
#include <math.h>

// TODO: Translate compute_and_merge_ref here.
// The function signature should be:
// void compute_and_merge(int n, int m, double* out_results)
EOF

    cat << 'EOF' > /home/user/app/c_src/Makefile
libpoly.so: poly.c
	gcc -o libpoly.so poly.c
EOF

    cat << 'EOF' > /home/user/app/api.py
from flask import Flask, request, jsonify
import json

app = Flask(__name__)

@app.route('/api/merge')
def merge_api():
    n = int(request.args.get('n', 10))
    m = int(request.args.get('m', 10))

    # TODO: Implement Redis caching
    # TODO: Call libpoly.so using ctypes

    return "Not implemented", 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /home/user/app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/ {
            # BROKEN PROXY PASS
            proxy_pass http://127.0.0.1:9999/;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/app/nginx.conf
gunicorn -w 4 -b 127.0.0.1:5000 api:app --daemon
EOF
    chmod +x /home/user/app/start_services.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
