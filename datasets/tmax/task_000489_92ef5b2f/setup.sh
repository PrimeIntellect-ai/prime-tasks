#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential redis-server curl libhiredis-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/src
    mkdir -p /home/user/app/build
    mkdir -p /home/user/app/backend
    mkdir -p /home/user/app/config
    mkdir -p /home/user/oracle

    # /home/user/app/src/parser.c
    cat << 'EOF' > /home/user/app/src/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *service;
    char *method;
    int bench;
    int retry;
} state_context;

char* parse_url(const char* url) {
    char buffer[256];
    state_context* ctx = malloc(sizeof(state_context));
    // Simulate parsing
    ctx->service = strdup("checkout");
    ctx->method = strdup("process");
    ctx->bench = 25;
    ctx->retry = 1;

    snprintf(buffer, sizeof(buffer), "{\"service\":\"%s\",\"method\":\"%s\",\"bench\":%d,\"retry\":%d}", 
             ctx->service, ctx->method, ctx->bench, ctx->retry);

    free(ctx->service);
    free(ctx->method);
    free(ctx);
    free(ctx); // double free bug

    return buffer; // stack return bug
}

#ifdef STANDALONE
int main() {
    char url[256];
    if (fgets(url, sizeof(url), stdin)) {
        char* res = parse_url(url);
        printf("%s\n", res);
    }
    return 0;
}
#endif
EOF

    # /home/user/app/Makefile
    cat << 'EOF' > /home/user/app/Makefile
CC = gcc
CFLAGS = -Wall -g

all: parser gateway

parser: src/parser.c
	$(CC) $(CFLAGS) -DSTANDALONE src/parser.c -o build/url_parser

gateway: src/gateway.c src/parser.c
	$(CC) $(CFLAGS) src/gateway.c src/parser.c -o build/gateway -lhiredis

clean:
	rm -rf build/*
EOF

    # /home/user/app/src/gateway.c (dummy to make Makefile work)
    cat << 'EOF' > /home/user/app/src/gateway.c
#include <stdio.h>
int main() {
    printf("Gateway running\n");
    return 0;
}
EOF

    # /home/user/app/backend/mock_grpc_server.py
    cat << 'EOF' > /home/user/app/backend/mock_grpc_server.py
import socket
import json

def run():
    print("Mock gRPC server listening on 50051")
    # Dummy implementation
    pass

if __name__ == '__main__':
    run()
EOF

    # /home/user/app/config/gateway.json
    cat << 'EOF' > /home/user/app/config/gateway.json
{
    "redis_port": 0,
    "grpc_backend_port": 0
}
EOF

    # /home/user/oracle/url_parser_oracle
    cat << 'EOF' > /home/user/oracle/url_parser_oracle
#!/bin/bash
read url
# Dummy oracle
echo '{"service":"checkout","method":"process","bench":25,"retry":1}'
EOF
    chmod +x /home/user/oracle/url_parser_oracle

    chmod -R 777 /home/user
