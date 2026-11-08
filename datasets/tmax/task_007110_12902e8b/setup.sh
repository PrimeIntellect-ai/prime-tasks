#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs /home/user/payloads

    cat << 'EOF' > /home/user/logs/frontend.log
[2023-10-27 10:12:05] USER: guest ACTION: login
[2023-10-27 10:14:22] USER: guest QUERY: fetch_data
[2023-10-27 10:15:30] USER: admin QUERY: update_record
[2023-10-27 10:15:45] USER: test QUERY: ping
EOF

    cat << 'EOF' > /home/user/logs/backend.log
[2023-10-27 10:14:22] TX: 8044 STATUS: OK
[2023-10-27 10:15:30] TX: 8045 STATUS: ERROR_DECODE
[2023-10-27 10:15:45] TX: 8046 STATUS: OK
EOF

    cat << 'EOF' > /home/user/backend.c
#include <stdio.h>
#include <stdint.h>

int process_payload(const char* filepath) {
    FILE *f = fopen(filepath, "rb");
    if (!f) return -1;
    uint32_t query_id;
    // BUG: Reading Big-Endian data directly into Little-Endian memory
    fread(&query_id, sizeof(uint32_t), 1, f);
    printf("Processing Query ID: %u\n", query_id);
    fclose(f);
    return 0;
}
EOF

    python3 -c 'open("/home/user/payloads/payload_8045.bin", "wb").write(b"\x00\x00\x01\xF4")'

    chmod -R 777 /home/user
