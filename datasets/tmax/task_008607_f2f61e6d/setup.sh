#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/log_ingestor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_file(const char *filename, const char *out_filename) {
    FILE *f = fopen(filename, "rb");
    FILE *out = fopen(out_filename, "wb");
    if(!f || !out) return;

    unsigned char magic[2];
    while (fread(magic, 1, 2, f) == 2) {
        if (magic[0] != 'L' || magic[1] != 'G') break;
        unsigned char type;
        if (fread(&type, 1, 1, f) != 1) break;
        unsigned char len;
        if (fread(&len, 1, 1, f) != 1) break;

        unsigned char payload[256];
        if (fread(payload, 1, len, f) != len) break;

        if (type == 1) {
            for (int i = 0; i < len / 2; i++) {
                unsigned char tmp = payload[i];
                payload[i] = payload[len - 1 - i];
                payload[len - 1 - i] = tmp;
            }
        } else if (type == 3) {
            int out_len = 0;
            unsigned char decoded[1024];
            for(int i=0; i<len; i+=2) {
                unsigned char count = payload[i];
                unsigned char val = payload[i+1];
                for(int j=0; j<count; j++) {
                    decoded[out_len++] = val; 
                }
            }
            fwrite(decoded, 1, out_len, out);
            continue;
        }

        fwrite(&type, 1, 1, out);
        fwrite(&len, 1, 1, out);
        fwrite(payload, 1, len, out);
    }
    fclose(f);
    fclose(out);
}

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    process_file(argv[1], argv[2]);
    return 0;
}
EOF

    printf "LG\x01\x04\x01\x02\x03\x04" > /home/user/data.bin
    printf "LG\x03\x0a\xff\xaa\xff\xaa\xff\xaa\xff\xaa\xff\xaa" > /home/user/crash.bin

    gcc /home/user/log_ingestor.c -o /home/user/log_ingestor

    chmod -R 777 /home/user
