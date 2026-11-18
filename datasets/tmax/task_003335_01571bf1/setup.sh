#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        zlib1g-dev \
        strace \
        ltrace \
        xxd \
        binutils \
        rustc \
        cargo

    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/normalizer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <zlib.h>

void replace_and_write(FILE *out, const char *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        if (i + 6 < len && strncmp(data + i, "MISSING", 7) == 0) {
            fputs("NaN", out);
            i += 6;
        } else if (i + 1 < len && data[i] == '\r' && data[i+1] == '\n') {
            fputc('\n', out);
            i++;
        } else {
            fputc(data[i], out);
        }
    }
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    FILE *in = fopen(argv[1], "rb");
    if (!in) return 1;

    char magic[5];
    if (fread(magic, 1, 5, in) != 5 || strncmp(magic, "RSRCH", 5) != 0) {
        fclose(in);
        return 1;
    }

    uint8_t c;
    if (fread(&c, 1, 1, in) != 1) {
        fclose(in);
        return 1;
    }

    char tmp_file[1024];
    snprintf(tmp_file, sizeof(tmp_file), "%s.tmp", argv[2]);
    FILE *out = fopen(tmp_file, "wb");
    if (!out) {
        fclose(in);
        return 1;
    }

    for (int i = 0; i < c; i++) {
        uint32_t uncomp_sz, comp_sz;
        if (fread(&uncomp_sz, 4, 1, in) != 1) break;
        if (fread(&comp_sz, 4, 1, in) != 1) break;

        unsigned char *comp_data = malloc(comp_sz);
        if (fread(comp_data, 1, comp_sz, in) != comp_sz) {
            free(comp_data);
            break;
        }

        unsigned char *uncomp_data = malloc(uncomp_sz);
        unsigned long destLen = uncomp_sz;
        if (uncompress(uncomp_data, &destLen, comp_data, comp_sz) == Z_OK) {
            replace_and_write(out, (char*)uncomp_data, destLen);
        }
        free(comp_data);
        free(uncomp_data);
    }

    fclose(in);
    fclose(out);
    rename(tmp_file, argv[2]);
    return 0;
}
EOF

    gcc -O2 /tmp/normalizer.c -o /app/dataset_normalizer -lz
    strip /app/dataset_normalizer
    rm /tmp/normalizer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
