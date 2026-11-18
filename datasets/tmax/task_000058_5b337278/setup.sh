#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip python3-venv python2 \
        nginx protobuf-compiler golang-go wget git

    pip3 install pytest

    # Create directories
    mkdir -p /app/legacy
    mkdir -p /app/services/proto
    mkdir -p /app/services/nginx
    mkdir -p /app/services/gateway
    mkdir -p /home/user/migrated

    # Legacy Python 2 script
    cat << 'EOF' > /app/legacy/process_v2.py
#!/usr/bin/env python2
import sys

records = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split('|')
    if len(parts) == 3:
        id_val = parts[0]
        ts = int(parts[1])
        vals = [float(x) for x in parts[2].split(',')]
        avg = round(sum(vals)/len(vals), 3)
        records.append((ts, id_val, avg))

records.sort(key=lambda x: (x[0], x[1]))

for r in records:
    print "{}|{}|{:.3f}".format(r[1], r[0], r[2])
EOF
    chmod +x /app/legacy/process_v2.py

    # Proto file
    cat << 'EOF' > /app/services/proto/data.proto
syntax = "proto3";
package data;
option go_package = "./;data";

service DataProcessor {
  rpc ProcessData (DataRequest) returns (DataResponse);
}

message DataRequest {
  string raw_payload = 1;
}

message DataResponse {
  string processed_payload = 1;
}
EOF

    # Nginx config
    cat << 'EOF' > /app/services/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        # location /api/process { proxy_pass http://localhost:5000; }
    }
}
EOF

    # Flask app
    cat << 'EOF' > /app/services/gateway/app.py
from flask import Flask, request

app = Flask(__name__)

@app.route('/api/process', methods=['POST'])
def process():
    # To be implemented
    pass

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Python venv
    python3 -m venv /app/services/gateway/venv
    /app/services/gateway/venv/bin/pip install Flask grpcio grpcio-tools

    # Go plugins for protoc
    export GOPATH=/opt/go
    go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2
    ln -s /opt/go/bin/protoc-gen-go /usr/local/bin/
    ln -s /opt/go/bin/protoc-gen-go-grpc /usr/local/bin/

    # User setup
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/migrated
    chmod -R 777 /home/user
    chmod -R 777 /app
