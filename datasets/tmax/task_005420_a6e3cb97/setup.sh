#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential git
    pip3 install pytest

    mkdir -p /app/picohttpparser
    git clone https://github.com/h2o/picohttpparser.git /app/picohttpparser

    cat << 'EOF' > /app/picohttpparser/Makefile
CC=clang-99
CFLAGS=-O2
all:
	$(CC) $(CFLAGS) -shared -o libpicohttpparser.so picohttpparser.c
EOF

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/req1.txt
GET /api/data HTTP/1.1
Host: example.com
X-SSL-Cert-Valid: SUCCESS
Authorization: Bearer secret_token_123

EOF

    cat << 'EOF' > /app/corpus/clean/req2.txt
POST /login HTTP/1.1
Host: example.com
X-SSL-Cert-Valid: SUCCESS
Content-Length: 0

EOF

    cat << 'EOF' > /app/corpus/evil/inj1.txt
GET /api/data?q=%27%20OR%201=1 HTTP/1.1
Host: example.com
X-SSL-Cert-Valid: SUCCESS
Authorization: Bearer secret_token_123

EOF

    cat << 'EOF' > /app/corpus/evil/xss1.txt
GET /api/data?user=<script>alert(1)</script> HTTP/1.1
Host: example.com
X-SSL-Cert-Valid: SUCCESS

EOF

    cat << 'EOF' > /app/corpus/evil/cert1.txt
GET /api/data HTTP/1.1
Host: example.com
Authorization: Bearer secret_token_123

EOF

    cat << 'EOF' > /app/corpus/evil/cert2.txt
GET /api/data HTTP/1.1
Host: example.com
X-SSL-Cert-Valid: FAILED

EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
