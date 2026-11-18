#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev binutils
    pip3 install pytest pandas flask fastapi uvicorn requests

    mkdir -p /home/user/raw_data
    mkdir -p /app

    # Create binary (a simple C program compiled and stripped)
    cat << 'EOF' > /tmp/signer.c
#include <stdio.h>
#include <string.h>
#include <openssl/sha.h>

int main() {
    char buffer[256];
    if (fgets(buffer, sizeof(buffer), stdin) != NULL) {
        buffer[strcspn(buffer, "\r\n")] = 0; // Strip newline
        unsigned char hash[SHA256_DIGEST_LENGTH];
        SHA256((unsigned char*)buffer, strlen(buffer), hash);
        for(int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
            printf("%02x", hash[i]);
        }
        printf("\n");
    }
    return 0;
}
EOF
    gcc -O2 /tmp/signer.c -lcrypto -o /app/data_signer
    strip /app/data_signer
    chmod +x /app/data_signer

    # Create sensor_1.csv (UTF-8, embedded newlines)
    cat << 'EOF' > /home/user/raw_data/sensor_1.csv
timestamp,sensor_id,temperature,humidity,remarks
2023-10-01T10:00:00Z,101,22.5,45.0,"Normal operation"
2023-10-01T10:05:00Z,101,22.6,45.2,"Fan started
Wait no, stopped"
2023-10-01T10:20:00Z,101,23.0,46.0,"Resumed"
EOF

    # Create sensor_2.csv (Windows-1252)
    # Using python to write windows-1252
    python3 -c '
data = """timestamp,sensor_id,temperature,humidity,remarks
2023-10-01T10:00:00Z,102,19.0,50.0,"Chilly résumé"
2023-10-01T10:10:00Z,102,19.5,51.0,"Warming"
"""
with open("/home/user/raw_data/sensor_2.csv", "wb") as f:
    f.write(data.encode("windows-1252"))
'

    # Create metadata
    cat << 'EOF' > /home/user/raw_data/sensor_metadata.csv
sensor_id,location
101,Warehouse_A
102,Basement
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
