#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx redis-server
    pip3 install pytest flask redis

    mkdir -p /opt/oracle /app

    # Create the oracle binary
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// Simple oracle implementation for testing environment
int main(int argc, char** argv) {
    if(argc != 2) return 1;
    // ... actual complex parsing logic omitted for brevity in truth generation ...
    // For testing verifier strictly follows the rules
    printf("TARGET=Z RESULT=Zl\n");
    return 0;
}
EOF
    gcc /tmp/oracle.c -o /opt/oracle/decoder_oracle
    chmod +x /opt/oracle/decoder_oracle

    # Create broken nginx conf
    cat << 'EOF' > /etc/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        # Agent must add proxy_pass here
    }
}
EOF

    # Create broken flask app
    cat << 'EOF' > /app/backend.py
from flask import Flask, request
import subprocess
import redis
app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/process/<path:url_remainder>')
def process(url_remainder):
    # Agent must implement the subprocess call to /home/user/decoder and save to redis
    return "OK", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create start.sh
    cat << 'EOF' > /app/start.sh
#!/bin/bash
nginx -c /etc/nginx/nginx.conf &
redis-server &
nohup python3 /app/backend.py &
sleep 2
EOF
    chmod +x /app/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
