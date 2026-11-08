#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/math_api.h
#ifndef MATH_API_H
#define MATH_API_H

// Parses a URL like "/api/add?a=10&b=20" and returns the sum in out_val.
// Returns 0 on success, -1 on invalid format.
int evaluate_url(const char* url, double* out_val);

#endif // MATH_API_H
EOF

    cat << 'EOF' > /home/user/math_api.c
#include "math_api.h"
#include <stdio.h>
#include <string.h>

int evaluate_url(const char* url, double* out_val) {
    double a, b;
    if (sscanf(url, "/api/add?a=%lf&b=%lf", &a, &b) == 2) {
        *out_val = a + b;
        return 0;
    }
    return -1;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
