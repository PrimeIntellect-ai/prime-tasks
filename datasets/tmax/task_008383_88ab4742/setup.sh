#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc make
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user/legacy_builder /home/user/db /home/user/grpc

    cat << 'EOF' > /home/user/legacy_builder/main.c
#include <stdio.h>

int main() {
    printf("Initializing build system...\n");
    printf(">>> BEGIN_ARTIFACT\n");
    printf("NAME: service_alpha_bin\n");
    printf("SIZE: 84500\n");
    printf("HASH: a1b2c3d4e5\n");
    printf("<<< END_ARTIFACT\n");
    printf("Linking dependencies...\n");
    printf(">>> BEGIN_ARTIFACT\n");
    printf("NAME: service_beta_bin\n");
    printf("SIZE: 128000\n");
    printf("HASH: f6g7h8i9j0\n");
    printf("<<< END_ARTIFACT\n");
    printf("Build complete.\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/legacy_builder/Makefile
builder: main.c
    gcc main.c -o
EOF

    sqlite3 /home/user/db/artifacts.db "CREATE TABLE artifacts (id INTEGER PRIMARY KEY, name TEXT, size INTEGER);"
    sqlite3 /home/user/db/artifacts.db "INSERT INTO artifacts (name, size) VALUES ('legacy_core', 45000);"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
