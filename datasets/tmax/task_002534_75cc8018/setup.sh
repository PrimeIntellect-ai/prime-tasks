#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create config
    cat << 'EOF' > /home/user/split.conf
intro.md:0:43
setup.md:43:52
api.md:95:48
EOF

    # Create docs_blob.bin with exactly 143 bytes to match test expectations
    python3 -c "
intro = b'# Introduction\nWelcome to the documentation.'[:43].ljust(43, b' ')
setup = b'# Setup\nRun the following commands to get started.'[:52].ljust(52, b' ')
api = b'# API\nThis section describes the API endpoints.'[:48].ljust(48, b' ')

data = intro + setup + api
encoded = bytes(b ^ 0x42 for b in data)

with open('/home/user/docs_blob.bin', 'wb') as f:
    f.write(encoded)
"

    # Create skeleton extractor.c
    cat << 'EOF' > /home/user/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>
#include <fcntl.h>

int main() {
    FILE *conf = fopen("/home/user/split.conf", "r");
    if (!conf) {
        perror("Failed to open config");
        return 1;
    }

    FILE *blob = fopen("/home/user/docs_blob.bin", "rb");
    if (!blob) {
        perror("Failed to open blob");
        return 1;
    }

    char line[256];
    while (fgets(line, sizeof(line), conf)) {
        char filename[128];
        long offset, length;

        // Parse the line: filename:offset:length
        if (sscanf(line, "%[^:]:%ld:%ld", filename, &offset, &length) != 3) {
            continue;
        }

        char out_path[256];
        snprintf(out_path, sizeof(out_path), "/home/user/output/%s", filename);

        // TODO: Read chunk from blob at offset, XOR with 0x42, write to out_path with flock(LOCK_EX)

    }

    fclose(blob);
    fclose(conf);
    return 0;
}
EOF

    chmod -R 777 /home/user
