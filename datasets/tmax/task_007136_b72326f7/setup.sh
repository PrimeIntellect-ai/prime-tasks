#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils libc6-dev
    pip3 install pytest

    mkdir -p /home/user/src
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/src/num.h
#ifndef NUM_H
#define NUM_H
double calc_entropy(const char* data);
#endif
EOF

    cat << 'EOF' > /home/user/src/num.c
#include "num.h"
#include <math.h>
#include <string.h>

double calc_entropy(const char* data) {
    int len = strlen(data);
    if (len == 0) return 0.0;
    int counts[256] = {0};
    for (int i = 0; i < len; i++) {
        counts[(unsigned char)data[i]]++;
    }
    double entropy = 0.0;
    for (int i = 0; i < 256; i++) {
        if (counts[i] > 0) {
            double p = (double)counts[i] / len;
            entropy -= p * log2(p);
        }
    }
    return entropy;
}
EOF

    cat << 'EOF' > /home/user/src/ws.h
#ifndef WS_H
#define WS_H
void ws_send(const char* msg);
void ws_fallback(const char* msg);
#endif
EOF

    cat << 'EOF' > /home/user/src/rest.h
#ifndef REST_H
#define REST_H
void rest_post(const char* data);
void rest_upgrade(const char* data);
#endif
EOF

    cat << 'EOF' > /home/user/src/ws.c
#include "ws.h"
#include "rest.h"
#include <stdio.h>

void ws_send(const char* msg) {
    printf("WS: %s\n", msg);
}

void ws_fallback(const char* msg) {
    rest_post(msg);
}
EOF

    cat << 'EOF' > /home/user/src/rest.c
#include "rest.h"
#include "ws.h"
#include <stdio.h>

void rest_post(const char* data) {
    printf("REST: %s\n", data);
}

void rest_upgrade(const char* data) {
    ws_send(data);
}
EOF

    cat << 'EOF' > /home/user/src/main.c
#include "num.h"
#include "rest.h"
#include "ws.h"
#include <stdio.h>

int main() {
    const char* payload = "SECURITY_PAYLOAD_TEST";
    double ent = calc_entropy(payload);
    printf("Entropy: %.4f\n", ent);
    rest_upgrade("Upgrade Request");
    ws_fallback("Fallback Request");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
