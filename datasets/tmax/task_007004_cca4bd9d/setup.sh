#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/router.h
#ifndef ROUTER_H
#define ROUTER_H
int cmp_version(const char* v1, const char* v2);
#endif
EOF

cat << 'EOF' > /home/user/router.c
#include "router.h"
#include <stdlib.h>

int cmp_version(const char* v1, const char* v2) {
    int a1, b1, c1;
    int a2, b2, c2;
    // Simple mock implementation for testing
    // In real life this would parse string to int safely
    a1 = atoi(v1); a2 = atoi(v2);
    if (a1 > a2) return 1;
    if (a1 < a2) return -1;

    // Quick hacky way to get second part for test cases
    const char *p1 = v1, *p2 = v2;
    while(*p1 && *p1 != '.') p1++; if(*p1) p1++;
    while(*p2 && *p2 != '.') p2++; if(*p2) p2++;
    b1 = atoi(p1); b2 = atoi(p2);
    if (b1 > b2) return 1;
    if (b1 < b2) return -1;

    while(*p1 && *p1 != '.') p1++; if(*p1) p1++;
    while(*p2 && *p2 != '.') p2++; if(*p2) p2++;
    c1 = atoi(p1); c2 = atoi(p2);
    if (c1 > c2) return 1;
    if (c1 < c2) return -1;

    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
