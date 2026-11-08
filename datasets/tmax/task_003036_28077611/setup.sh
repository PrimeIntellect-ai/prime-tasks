#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils libc6-dev
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app

    cat << 'EOF' > auth.c
#include <stdio.h>

extern int verify_signature(const char* data);

int authenticate_user() {
    printf("Starting authentication...\n");
    if (verify_signature("user_payload")) {
        printf("Authentication Success\n");
        return 0;
    } else {
        printf("Authentication Failed\n");
        return 1;
    }
}
EOF

    cat << 'EOF' > server.c
#include <stdio.h>

extern int authenticate_user();

int main() {
    authenticate_user();
    return 0;
}
EOF

    gcc -fPIC -shared -Wl,--allow-shlib-undefined -o libauth.so auth.c
    gcc -o server_bin server.c -L. -lauth -Wl,-rpath=. -Wl,--allow-shlib-undefined

    rm auth.c server.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
