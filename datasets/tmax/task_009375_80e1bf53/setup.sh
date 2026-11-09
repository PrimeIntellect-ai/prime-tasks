#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > encode.h
#ifndef ENCODE_H
#define ENCODE_H
void url_encode(const char *src, char *dest);
#endif
EOF

    cat << 'EOF' > encode.c
#include "encode.h"
#include <stdio.h>
void url_encode(const char *src, char *dest) {
    while (*src) {
        if (*src == ' ') {
            *dest++ = '%'; *dest++ = '2'; *dest++ = '0';
        } else {
            *dest++ = *src;
        }
        src++;
    }
    *dest = '\0';
}
EOF

    cat << 'EOF' > router.h
#ifndef ROUTER_H
#define ROUTER_H
#include "endpoint.h"

typedef struct Router {
    Endpoint* endpoints[10];
    int count;
} Router;

void init_router(Router* r);
void add_endpoint(Router* r, Endpoint* e);
#endif
EOF

    cat << 'EOF' > router.c
#include "router.h"
void init_router(Router* r) {
    r->count = 0;
}
void add_endpoint(Router* r, Endpoint* e) {
    if (r->count < 10) {
        r->endpoints[r->count++] = e;
    }
}
EOF

    cat << 'EOF' > endpoint.h
#ifndef ENDPOINT_H
#define ENDPOINT_H
#include "router.h"

typedef struct Endpoint {
    char path[256];
    Router* parent;
} Endpoint;

void init_endpoint(Endpoint* e, const char* path, Router* parent);
#endif
EOF

    cat << 'EOF' > endpoint.c
#include "endpoint.h"
#include <string.h>
void init_endpoint(Endpoint* e, const char* path, Router* parent) {
    strncpy(e->path, path, 255);
    e->path[255] = '\0';
    e->parent = parent;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
