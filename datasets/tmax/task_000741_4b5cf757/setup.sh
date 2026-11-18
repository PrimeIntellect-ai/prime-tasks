#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/http_parser.h
#ifndef HTTP_PARSER_H
#define HTTP_PARSER_H

typedef struct {
    char method[16];
    char path[256];
    int status;
} http_request_t;

void parse_request(const char *raw, http_request_t *req);

#endif
EOF

    cat << 'EOF' > /home/user/workspace/http_parser.c
#include "http_parser.h"

void parse_request(const char *raw, http_request_t *req) {
    int state = 0; 
    int i = 0, m = 0, p = 0;
    req->status = 0;
    req->method[0] = '\0';
    req->path[0] = '\0';

    while (raw[i] != '\0') {
        char c = raw[i];
        if (state == 0) {
            if (c == ' ') { 
                state = 1; 
                req->method[m] = '\0'; 
            } else { 
                req->method[m++] = c; 
            }
        } else if (state == 1) {
            if (c == ' ') { 
                state = 2; 
                req->path[p] = '\0'; 
            }
            // BUG: Missing logic to copy path characters
            // else { req->path[p++] = c; }
        } else if (state == 2) {
            if (c == '\r' && raw[i+1] == '\n') {
                state = 3;
                req->status = 1;
                break;
            }
        }
        i++;
    }
}
EOF

    cat << 'EOF' > /home/user/workspace/test_http_parser.c
#include "http_parser.h"
#include <stdio.h>
#include <string.h>

int main() {
    http_request_t req;
    parse_request("GET /api/v1/users?id=123 HTTP/1.1\r\n\r\n", &req);

    if (req.status == 1 && 
        strcmp(req.method, "GET") == 0 && 
        strcmp(req.path, "/api/v1/users?id=123") == 0) {
        printf("ALL TESTS PASSED\n");
        return 0;
    }
    printf("TEST FAILED\n");
    return 1;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
