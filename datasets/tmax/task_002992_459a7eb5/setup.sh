#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip protobuf-compiler time
pip3 install pytest protobuf

mkdir -p /home/user

cat << 'EOF' > /home/user/urls.txt
https://api.example.com/v1/users
http://legacy.internal.net/status
https://grpc.service.org/v2/update
EOF

cat << 'EOF' > /home/user/request.proto
syntax = "proto3";
message RouteRequest {
    string url = 1;
    string domain = 2;
    int32 rate_limit = 3;
}
EOF

cat << 'EOF' > /home/user/legacy_parser.py
import urlparse
import sys
import request_pb2

def parse(url):
    parsed = urlparse.urlparse(url)
    req = request_pb2.RouteRequest()
    req.url = url
    req.domain = parsed.netloc
    req.rate_limit = 10

    # Write binary to stdout
    sys.stdout.write(req.SerializeToString())

if __name__ == "__main__":
    if len(sys.argv) > 1:
        parse(sys.argv[1])
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
