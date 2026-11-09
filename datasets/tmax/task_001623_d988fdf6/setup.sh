#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make protobuf-c-compiler libprotobuf-c-dev
    pip3 install pytest

    mkdir -p /home/user/gateway_test

    cat << 'EOF' > /home/user/gateway_test/gateway.proto
syntax = "proto3";
message RouteRequest {
    string path = 1;
    string parameter = 2;
}
EOF

    cat << 'EOF' > /home/user/gateway_test/gateway.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "gateway.pb-c.h"

void parse_url_and_route(const char* url) {
    // URL format: /route?param=VALUE
    char path[50] = {0};
    char param[10] = {0}; // BUG: Buffer is too small for the test parameter

    // BUG: %s can overflow the param buffer
    sscanf(url, "%49[^?]?param=%s", path, param);

    RouteRequest req = ROUTE_REQUEST__INIT;
    req.path = path;
    req.parameter = param;

    size_t len = route_request__get_packed_size(&req);
    uint8_t *buf = malloc(len);
    route_request__pack(&req, buf);

    FILE *f = fopen("/home/user/gateway_test/qa_success.log", "w");
    if (f) {
        fprintf(f, "Path: %s, Param: %s, PackedSize: %zu\n", req.path, req.parameter, len);
        fclose(f);
    }
    free(buf);
}

int main() {
    // Test URL with a parameter significantly longer than 10 characters
    parse_url_and_route("/api/v2/users?param=SuperLongParameter1234567890");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/gateway_test/Makefile
all: gateway_test

gateway.pb-c.c gateway.pb-c.h: gateway.proto
	protoc-c --c_out=. gateway.proto

gateway_test: gateway.c gateway.pb-c.c
	gcc -g -O0 -o gateway_test gateway.c gateway.pb-c.c -lprotobuf-c

clean:
	rm -f gateway_test gateway.pb-c.* qa_success.log
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/gateway_test
    chmod -R 777 /home/user
