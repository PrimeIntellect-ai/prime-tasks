#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx
    pip3 install --default-timeout=100 pytest flask pyjwt

    mkdir -p /app/nginx /app/flask /app/data /app/bin /app/oracle

    # Nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /auth/ {
            # TODO: add proxy_pass
        }
    }
}
EOF

    # Flask config
    cat << 'EOF' > /app/flask/config.py
import os
SECRET_KEY = "weak_default"
EOF

    # Flask app
    cat << 'EOF' > /app/flask/app.py
from flask import Flask, request, jsonify
import jwt
import config

app = Flask(__name__)
app.config.from_object(config)

@app.route('/', methods=['POST', 'GET'])
def index():
    token = jwt.encode({"admin": True}, app.config['SECRET_KEY'], algorithm="HS256")
    return jsonify({"token": token})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Admin hash
    echo "11b9842e0a271ff252c1903e7132cd68" > /app/data/admin_hash.txt

    # Legacy binary
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    char *token = argv[1];
    char *resource = argv[2];

    int token_sum = 0;
    for(int i=0; i<16; i+=2) {
        char buf[3] = {token[i], token[i+1], 0};
        token_sum += (int)strtol(buf, NULL, 16);
    }

    int resource_sum = 0;
    for(int i=0; resource[i]; i++) {
        resource_sum += resource[i];
    }

    int diff = token_sum - resource_sum;
    if (diff < 0) diff = -diff;

    if (diff % 7 == 0) {
        printf("ALLOW\n");
    } else {
        printf("DENY\n");
    }
    return 0;
}
EOF
    gcc -O2 /tmp/legacy.c -o /app/bin/legacy_perm_check
    strip /app/bin/legacy_perm_check
    rm /tmp/legacy.c

    # Oracle
    cat << 'EOF' > /app/oracle/reference_perm_check.py
#!/usr/bin/env python3
import sys

def check_perm(token, resource):
    token_sum = sum(int(token[i:i+2], 16) for i in range(0, 16, 2))
    resource_sum = sum(ord(c) for c in resource)
    if abs(token_sum - resource_sum) % 7 == 0:
        print("ALLOW")
    else:
        print("DENY")

if __name__ == "__main__":
    check_perm(sys.argv[1], sys.argv[2])
EOF
    chmod +x /app/oracle/reference_perm_check.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
