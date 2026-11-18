#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils curl
    pip3 install pytest

    mkdir -p /app/legacy_libs

    # Create dummy helper library
    cat << 'EOF' > /tmp/helpers.c
void dummy_helper() {}
EOF
    gcc -shared -fPIC -o /app/legacy_libs/libhelpers.so.1 /tmp/helpers.c

    # Create solver library
    cat << 'EOF' > /tmp/solver.c
void dummy_helper();
int run_solver(int target, int* weights, int count) {
    dummy_helper();
    int sum = 0;
    for (int i = 0; i < count; i++) {
        sum += weights[i];
    }
    return target - sum;
}
EOF
    ln -s /app/legacy_libs/libhelpers.so.1 /app/legacy_libs/libhelpers.so
    gcc -shared -fPIC -o /app/libsolver.so /tmp/solver.c -L/app/legacy_libs -lhelpers
    rm /app/legacy_libs/libhelpers.so

    # Create oracle parser
    cat << 'EOF' > /tmp/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *url = argv[1];
    int target = 0;
    char *w_str = NULL;

    char *target_ptr = strstr(url, "target=");
    if (target_ptr) {
        target = atoi(target_ptr + 7);
    }

    char *w_ptr = strstr(url, "w=");
    if (w_ptr) {
        w_str = w_ptr + 2;
    }

    printf("{\"target\": %d, \"weights\": [", target);
    if (w_str) {
        char *token = strtok(w_str, ",");
        int first = 1;
        while (token) {
            if (!first) printf(", ");
            printf("%d", atoi(token));
            first = 0;
            token = strtok(NULL, ",");
        }
    }
    printf("]}\n");
    return 0;
}
EOF
    gcc -o /app/oracle_parser /tmp/parser.c
    strip /app/oracle_parser

    # Create api template
    cat << 'EOF' > /app/api_template.py
import ctypes
import json
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

# Load libsolver.so
# solver = ctypes.CDLL('/app/libsolver.so')

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # TODO: implement
        pass

if __name__ == '__main__':
    # TODO: start server on 127.0.0.1:8080
    pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
