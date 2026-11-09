#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/server_bin.c
#include <stdio.h>
int main() {
    const char* conf1 = "TRUSTED_DOMAIN=secure.internal.corp";
    const char* conf2 = "SECRET_COOKIE_NAME=Admin_X_Session_Token";
    printf("%s %s", conf1, conf2);
    return 0;
}
EOF
    gcc /home/user/server_bin.c -o /home/user/server_bin
    rm /home/user/server_bin.c

    cat << 'EOF' > /home/user/traffic.jsonl
{"request_id": "req-001", "method": "GET", "url": "/login?redirect=https://secure.internal.corp/admin", "headers": {"Cookie": "Admin_X_Session_Token=secret123; user_pref=dark", "User-Agent": "curl/7.68.0"}}
{"request_id": "req-002", "method": "GET", "url": "/login?redirect=http://evil-phishing.com/login", "headers": {"Cookie": "session=normaluser", "User-Agent": "Mozilla/5.0"}}
{"request_id": "req-003", "method": "POST", "url": "/login", "headers": {"Cookie": "Admin_X_Session_Token=super_secret_456", "User-Agent": "Chrome/100.0"}}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
