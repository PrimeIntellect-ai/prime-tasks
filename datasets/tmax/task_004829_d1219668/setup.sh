#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/sensor_decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    char magic[9] = {0};
    fread(magic, 1, 8, f);
    if (strncmp(magic, "WALMAGIC", 8) != 0) {
        printf("Invalid magic\n");
        fclose(f);
        return 1;
    }
    char sensor_id[17] = {0};
    fread(sensor_id, 1, 16, f);
    fclose(f);

    printf("[DEBUG] Initializing WAL decoder v1.4...\n");
    printf("[INFO] Scanning blocks...\n");
    printf("[META] SensorID: %s\n", sensor_id);
    printf("[INFO] Extraction complete.\n");
    return 0;
}
EOF

    gcc /app/sensor_decoder.c -o /app/sensor_decoder -s
    chmod +x /app/sensor_decoder
    rm /app/sensor_decoder.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
