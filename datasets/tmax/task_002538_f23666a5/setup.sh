#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest flask requests

    mkdir -p /home/user/src /home/user/lib

    cat << 'EOF' > /home/user/src/checksum.c
#include <stdint.h>

uint32_t compute_checksum(const char* data, int len) {
    uint32_t sum = 0;
    for(int i=0; i<len; i++) {
        sum = (sum + data[i]) % 256;
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/schema_v1.json
{
  "legacy_flag": true,
  "users": [
    {"id": 1, "name": "Alice"},
    {"id": 2, "name": "Bob"}
  ],
  "environment": "production"
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
