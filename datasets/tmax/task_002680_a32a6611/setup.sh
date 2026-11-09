#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/hidden_tests
    cat << 'EOF' > /home/user/hidden_tests/req1.txt
GET /artifacts/release/v2.1.0/bin.tar.gz HTTP/1.1
Host: artifacts.local
X-Build-Token: A1B2C3D4E5F67890
Accept: */*

EOF

    cat << 'EOF' > /home/user/hidden_tests/req2.txt
GET /artifacts/%2E%2E%2F%2E%2E%2Fetc%2Fpasswd HTTP/1.1
Host: artifacts.local
X-Build-Token: aabbccddeeff0011

EOF

    cat << 'EOF' > /home/user/hidden_tests/req3.txt
GET /downloads/v1.0.0/build.zip HTTP/1.1
Host: artifacts.local
X-Build-Token: 1234567890abcdef

EOF

    cat << 'EOF' > /home/user/hidden_tests/req4.txt
GET /artifacts/latest.zip HTTP/1.1
Host: artifacts.local
X-Build-Token: short

EOF

    cat << 'EOF' > /home/user/hidden_tests/req5.txt
GET /artifacts/latest.zip HTTP/1.1
Host: artifacts.local

EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
