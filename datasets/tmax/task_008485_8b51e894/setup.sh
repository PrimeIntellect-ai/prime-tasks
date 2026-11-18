#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/util_dev

    cat << 'EOF' > /home/user/util_dev/legacy_parser.py
import sys
from collections import defaultdict

counts = defaultdict(int)

for line in sys.stdin:
    line = line.strip()
    if not line: continue
    parts = line.split()
    if len(parts) != 3: continue
    ts, ip, hex_uri = parts

    try:
        uri = bytes.fromhex(hex_uri).decode('ascii')
    except:
        continue

    if uri.startswith("/api/v1/"):
        counts[ip] += 1

for ip, count in counts.items():
    if count > 2:
        print(f"{ip} {count}")
EOF

    cat << 'EOF' > /home/user/util_dev/fast_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_IPS 1000

typedef struct {
    char ip[64];
    int count;
} IPCounter;

IPCounter counters[MAX_IPS];
int num_ips = 0;

int hex_to_int(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    // BUG: Missing handling for lowercase 'a'-'f'
    return 0; 
}

void decode_hex(const char *hex, char *out) {
    int len = strlen(hex);
    for (int i = 0; i < len; i += 2) {
        out[i/2] = (hex_to_int(hex[i]) << 4) | hex_to_int(hex[i+1]);
    }
    out[len/2] = '\0';
}

void add_ip(const char *ip) {
    for (int i = 0; i < num_ips; i++) {
        if (strcmp(counters[i].ip, ip) == 0) {
            counters[i].count++;
            return;
        }
    }
    strcpy(counters[num_ips].ip, ip);
    counters[num_ips].count = 1;
    num_ips++;
}

int main() {
    char ts[64], ip[64], hex_uri[1024], uri[512];

    while (scanf("%63s %63s %1023s", ts, ip, hex_uri) == 3) {
        decode_hex(hex_uri, uri);
        if (strncmp(uri, "/api/v1/", 8) == 0) {
            add_ip(ip);
        }
    }

    for (int i = 0; i < num_ips; i++) {
        if (counters[i].count > 2) {
            printf("%s %d\n", counters[i].ip, counters[i].count);
        }
    }
    return 0;
}
EOF

    chmod +x /home/user/util_dev/legacy_parser.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
