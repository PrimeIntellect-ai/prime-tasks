#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ gdb binutils git wget
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Create legacy_auth.c and compile it
    cat << 'EOF' > legacy_auth.c
#include <stdio.h>
#include <string.h>
int check_token(const char* input) {
    char token[17];
    // Constructs "X9fK_master_2024"
    strncpy(token, "X9fK", 4);
    strncpy(token+4, "_master_", 8);
    strncpy(token+12, "2024", 5);
    return strcmp(input, token) == 0;
}
int main(int argc, char** argv) {
    if (argc > 1) return check_token(argv[1]);
    return 1;
}
EOF
    gcc legacy_auth.c -o legacy_auth
    rm legacy_auth.c

    # Create traffic.raw
    cat << 'EOF' > traffic.raw
GET /admin HTTP/1.1
Host: example.com
Authorization: Bearer X9fK_master_2024
Accept: */*

GET /public HTTP/1.1
Host: example.com
Cookie: session=X9fK_master_2024
Accept: */*

GET /admin HTTP/1.1
Host: example.com
Accept: */*

EOF

    # Setup picohttpparser
    git clone https://github.com/h2o/picohttpparser.git /app/picohttpparser-2.1
    cd /app/picohttpparser-2.1
    git checkout v2.1 || true
    # Inject deliberate typo
    sed -i 's/#include <string.h>/#include <sting.h>/g' picohttpparser.c

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
