#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/server
    mkdir -p /home/user/rotator

    cat << 'EOF' > /home/user/server/users.json
[
  {"username": "alice", "token": "tok_111"},
  {"username": "bob", "token": "tok_222"},
  {"username": "charlie", "token": "tok_333"},
  {"username": "david", "token": "tok_444"}
]
EOF

    cat << 'EOF' > /home/user/server/access.log
[2023-10-01T12:00:00Z] GET /login?redirect=http://internal.corp/dashboard&token=tok_111 HTTP/1.1 302
[2023-10-01T12:05:00Z] GET /login?redirect=http://evil.com/steal&token=tok_222 HTTP/1.1 302
[2023-10-01T12:10:00Z] GET /login?redirect=https://hacker.net/&token=tok_333 HTTP/1.1 302
[2023-10-01T12:15:00Z] GET /login?redirect=http://localhost:8080/&token=tok_444 HTTP/1.1 302
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
