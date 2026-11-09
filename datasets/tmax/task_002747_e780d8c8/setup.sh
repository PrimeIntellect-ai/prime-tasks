#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl build-essential libelf-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    cd /home/user/app

    # 1. Create Certificates
    openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/CN=AuditCA"
    openssl req -newkey rsa:2048 -keyout server.key -out server.csr -nodes -subj "/CN=legacy.local"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365

    # 2. Create the legacy_endpoint ELF binary
    cat << 'EOF' > legacy_endpoint.c
#include <stdio.h>
const char audit_data[] __attribute__((section(".audit_config"))) = "AUTH_TOKEN=Z79_Compliance_Req;IDS_PATTERN=^(GET|POST).*DROP_TABLE.*";

int main() {
    printf("Legacy endpoint running...\n");
    return 0;
}
EOF
    gcc legacy_endpoint.c -o legacy_endpoint

    # 3. Create traffic.log
    cat << 'EOF' > traffic.log
GET /index.html HTTP/1.1
POST /login HTTP/1.1
GET /api/data?query=DROP_TABLE_USERS HTTP/1.1
PUT /upload HTTP/1.1
POST /api/query?cmd=DROP_TABLE_ADMINS HTTP/1.1
GET /health HTTP/1.1
EOF

    chmod -R 777 /home/user
