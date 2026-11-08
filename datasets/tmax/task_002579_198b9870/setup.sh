#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget tar zlib1g-dev
    pip3 install pytest

    # Prepare zlib-1.3 source
    mkdir -p /app
    cd /app
    wget -q https://github.com/madler/zlib/releases/download/v1.3/zlib-1.3.tar.gz || wget -q https://zlib.net/zlib-1.3.tar.gz
    tar -xzf zlib-1.3.tar.gz
    rm zlib-1.3.tar.gz

    # Apply perturbation
    sed -i 's/deflate\.o//g' /app/zlib-1.3/Makefile.in
    sed -i 's/deflate\.lo//g' /app/zlib-1.3/Makefile.in

    # Create oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <zlib.h>

int main() {
    char path[4096];
    while (fgets(path, sizeof(path), stdin)) {
        size_t len = strlen(path);
        if (len > 0 && path[len-1] == '\n') {
            path[len-1] = '\0';
            len--;
        }
        if (len == 0) continue;

        FILE *f = fopen(path, "rb");
        if (!f) continue;

        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);

        if (size < 0) {
            fclose(f);
            continue;
        }

        uint32_t orig_size = (uint32_t)size;
        unsigned char *buf = NULL;
        if (orig_size > 0) {
            buf = malloc(orig_size);
            if (!buf) {
                fclose(f);
                continue;
            }
            size_t read_bytes = fread(buf, 1, orig_size, f);
            if (read_bytes != orig_size) {
                free(buf);
                fclose(f);
                continue;
            }
        }
        fclose(f);

        uLongf comp_len = compressBound(orig_size);
        unsigned char *comp_buf = malloc(comp_len);
        if (!comp_buf) {
            if (buf) free(buf);
            continue;
        }

        if (compress(comp_buf, &comp_len, buf, orig_size) != Z_OK) {
            if (buf) free(buf);
            free(comp_buf);
            continue;
        }

        uint16_t path_len = (uint16_t)len;
        uint32_t comp_size = (uint32_t)comp_len;

        fwrite(&path_len, sizeof(path_len), 1, stdout);
        fwrite(path, 1, path_len, stdout);
        fwrite(&orig_size, sizeof(orig_size), 1, stdout);
        fwrite(&comp_size, sizeof(comp_size), 1, stdout);
        fwrite(comp_buf, 1, comp_size, stdout);

        if (buf) free(buf);
        free(comp_buf);
    }
    return 0;
}
EOF

    gcc -O2 /opt/oracle/oracle.c -o /opt/oracle/my_archiver -lz
    rm /opt/oracle/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
