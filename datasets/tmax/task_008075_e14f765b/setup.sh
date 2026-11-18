#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/calculator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int evaluate_hex_expression(const char* hex_str, double* result) {
    char expr[256] = {0};
    size_t len = strlen(hex_str);
    if(len % 2 != 0 || len > 500) return -1;
    for(size_t i=0; i<len; i+=2) {
        sscanf(hex_str + i, "%2hhx", &expr[i/2]);
    }
    double a, b;
    char op;
    if (sscanf(expr, "%lf%c%lf", &a, &op, &b) != 3) return -1;
    if (op == '+') *result = a + b;
    else if (op == '-') *result = a - b;
    else if (op == '*') *result = a * b;
    else if (op == '/') *result = a / b;
    else return -1;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/workspace/service.proto
syntax = "proto3";
package mathpkg;

service MathService {
    rpc Compute (ComputeRequest) returns (ComputeResponse);
}

message ComputeRequest {
    string hex_payload = 1;
}

message ComputeResponse {
    double result = 1;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
