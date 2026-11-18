#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/investigation/uploads
    mkdir -p /home/user/hidden_stash

    cat << 'EOF' > /home/user/investigation/upload_handler.c
#include <stdio.h>
#include <string.h>

void handle_upload(char* filename_param) {
    char base_dir[] = "/home/user/investigation/uploads/";
    char filepath[512];

    // Vulnerable: no sanitization of filename_param for ../
    snprintf(filepath, sizeof(filepath), "%s%s", base_dir, filename_param);

    printf("Saving file to: %s\n", filepath);
}
EOF

    cat << 'EOF' > /home/user/investigation/access.log
192.168.1.100 - - [10/Oct/2023:13:55:36 -0000] "GET /index.html HTTP/1.1" 200 1024 "-" "Mozilla/5.0" "-"
192.168.1.100 - - [10/Oct/2023:13:56:12 -0000] "POST /upload?filename=test.txt HTTP/1.1" 201 128 "-" "Mozilla/5.0" "session=valid1"
192.168.1.105 - - [10/Oct/2023:13:58:11 -0000] "POST /upload?filename=..%2f..%2fhidden_stash%2fpayload.enc HTTP/1.1" 201 512 "-" "curl/7.68.0" "session=aB39"
EOF

    python3 -c '
import os
key = b"aB394271"
pt = b"EVIDENCE{path_traversal_and_brute_force_master_9921}"
ct = bytes([pt[i] ^ key[i % len(key)] for i in range(len(pt))])
os.makedirs("/home/user/hidden_stash", exist_ok=True)
with open("/home/user/hidden_stash/payload.enc", "wb") as f:
    f.write(ct)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
