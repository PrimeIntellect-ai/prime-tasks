#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc redis-server nginx curl
    pip3 install pytest

    mkdir -p /app/backend
    mkdir -p /app/nginx

    # Create oracle.c and compile
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    int major, minor, patch;
    if (sscanf(argv[1], "%d.%d.%d", &major, &minor, &patch) != 3) return 1;
    int n = atoi(argv[2]);

    int res = (major * 100) + (minor * 10) + patch + (n * 3);
    printf("%d\n", res);
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/legacy_oracle
    strip /app/legacy_oracle
    rm /tmp/oracle.c

    # Create broken pyproject.toml
    cat << 'EOF' > /app/backend/pyproject.toml
[build-system]
requires = ["setuptools>=40.8.0", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "math_backend"
version = "1.0.0"
dependencies = [
    "Flask==0.10.1",
    "redis==2.10.6",
    "legacy-math-ext==0.0.1"
]
EOF

    # Create app.py
    cat << 'EOF' > /app/backend/app.py
from flask import Flask, request
import redis
# legacy_math_ext is broken/missing
import legacy_math_ext 

app = Flask(__name__)
cache = redis.Redis(host='localhost', port=6379)

@app.route('/api/math')
def math_endpoint():
    v = request.args.get('v')
    n = request.args.get('n')
    if not v or not n:
        return "Missing args", 400

    cache_key = f"{v}:{n}"
    cached = cache.get(cache_key)
    if cached:
        return cached.decode('utf-8')

    # Needs to be replaced with subprocess call to /home/user/math_worker.sh
    res = str(legacy_math_ext.compute(v, int(n)))

    cache.set(cache_key, res)
    return res

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create nginx.conf
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
