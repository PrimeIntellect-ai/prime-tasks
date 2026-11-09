#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq xxd
    pip3 install pytest

    mkdir -p /home/user/artifacts/clean
    mkdir -p /home/user/artifacts/evil
    mkdir -p /app

    cat << 'EOF' > /tmp/artifact_reader.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    unsigned char bom[2];
    fread(bom, 1, 2, f);
    fseek(f, 0, SEEK_SET);

    char json_buf[256] = {0};
    if (bom[0] == 0xFF && bom[1] == 0xFE) {
        // Mock UTF-16LE handling (very naive for the sake of the mock)
        unsigned char raw[128];
        fread(raw, 1, 128, f);
        int j = 0;
        for(int i=2; i<128; i+=2) {
            if (raw[i] != 0) json_buf[j++] = raw[i];
        }
    } else {
        fread(json_buf, 1, 64, f);
    }

    // Extract data_size naively
    long data_size = 0;
    char *ptr = strstr(json_buf, "\"data_size\"");
    if (ptr) {
        sscanf(ptr, "\"data_size\" : %ld", &data_size);
        sscanf(ptr, "\"data_size\":%ld", &data_size);
    }

    if (data_size > 0) {
        // Vulnerable simulation: if size is too big, simulate crash
        fseek(f, 0, SEEK_END);
        long real_size = ftell(f);
        if (data_size > real_size * 2) {
            // Simulate segfault
            int *crash = NULL;
            *crash = 1; 
        }
    }

    printf("Processed successfully.\n");
    fclose(f);
    return 0;
}
EOF
    gcc /tmp/artifact_reader.c -o /app/artifact_reader
    strip /app/artifact_reader
    rm /tmp/artifact_reader.c

    printf '{"data_size": 100}\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0' > /home/user/artifacts/clean/clean1.bin
    head -c 100 /dev/urandom >> /home/user/artifacts/clean/clean1.bin

    python3 -c '
import sys
hdr = b"{\"data_size\": 50}".ljust(64, b"\x00")
sys.stdout.buffer.write(hdr.decode("utf-8").encode("utf-16-le"))
' > /home/user/artifacts/clean/clean2.bin
    head -c 50 /dev/urandom >> /home/user/artifacts/clean/clean2.bin

    printf '{"data_size": 999999}\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0' > /home/user/artifacts/evil/evil1.bin
    head -c 100 /dev/urandom >> /home/user/artifacts/evil/evil1.bin

    python3 -c '
import sys
hdr = b"{\"data_size\": 888888}".ljust(64, b"\x00")
sys.stdout.buffer.write(hdr.decode("utf-8").encode("utf-16-le"))
' > /home/user/artifacts/evil/evil2.bin
    head -c 50 /dev/urandom >> /home/user/artifacts/evil/evil2.bin

    chmod +x /app/artifact_reader

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user
