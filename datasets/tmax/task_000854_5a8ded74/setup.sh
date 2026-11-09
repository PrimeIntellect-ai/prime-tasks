#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx build-essential
    pip3 install pytest

    mkdir -p /home/user/app/lib
    mkdir -p /home/user/app/nginx

    cat << 'EOF' > /home/user/app/lib/libtransform.c
#include <string.h>

int transform_data_v2(const char* input, int len, char* output) {
    if (!input || !output) return -1;
    for (int i = 0; i < len; i++) {
        output[i] = input[i] + 1; 
    }
    output[len] = '\0';
    return len;
}
EOF

    gcc -shared -o /home/user/app/lib/libtransform.so -fPIC /home/user/app/lib/libtransform.c
    rm /home/user/app/lib/libtransform.c

    cat << 'EOF' > /home/user/app/lib/transform.h
/* Legacy header - might be outdated */
int transform(char* input, char* output);
EOF

    cat << 'EOF' > /home/user/app/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/app/nginx/error.log;
pid /home/user/app/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    # TODO: Configure server on 8080 routing /api/process to backend
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
