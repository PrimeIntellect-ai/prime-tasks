#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc file binutils xxd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create Nginx error log
    cat << 'EOF' > /home/user/nginx_error.log
2023/10/24 10:15:32 [error] 12345#0: *100 FastCGI sent in stderr: "Segmentation fault (core dumped)" while reading response header from upstream, client: 10.0.0.5, server: api.local, request: "GET /auth?token=XYZ123 HTTP/1.1", upstream: "fastcgi://127.0.0.1:9000", host: "api.local"
EOF

    # Create /app directory
    mkdir -p /app

    # Create C source file
    cat << 'EOF' > /tmp/auth_backend.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *input = argv[1];
    int len = strlen(input);
    printf("VALID-");
    for (int i = len - 1; i >= 0; i--) {
        printf("%02X", (unsigned char)input[i]);
    }
    printf("-ACK\n");
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -o /app/auth_backend /tmp/auth_backend.c
    strip /app/auth_backend
    chmod +x /app/auth_backend

    # Clean up
    rm /tmp/auth_backend.c

    chmod -R 777 /home/user
