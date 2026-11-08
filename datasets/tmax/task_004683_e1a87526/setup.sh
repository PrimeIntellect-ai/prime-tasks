#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/doc_compiler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }

    bool render_hidden = true;
    FILE *cfg = fopen("/home/user/compiler_config.ini", "r");
    if (cfg) {
        char line[256];
        while (fgets(line, sizeof(line), cfg)) {
            if (strstr(line, "render_hidden=false") || strstr(line, "render_hidden = false")) {
                render_hidden = false;
            }
        }
        fclose(cfg);
    }

    FILE *in = fopen(argv[1], "rb");
    if (!in) return 1;

    uint8_t magic[6];
    if (fread(magic, 1, 6, in) != 6 || memcmp(magic, "\x89TDOC\x00", 6) != 0) {
        fprintf(stderr, "ERROR: Invalid magic bytes\n");
        fclose(in);
        return 1;
    }

    char *out_buf = NULL;
    size_t out_len = 0;
    FILE *out_mem = open_memstream(&out_buf, &out_len);

    while (1) {
        uint8_t type;
        if (fread(&type, 1, 1, in) != 1) {
            fprintf(stderr, "ERROR: Unexpected end of file\n");
            fclose(in);
            fclose(out_mem);
            free(out_buf);
            return 2;
        }

        if (type == 0xFF) {
            fclose(out_mem);
            FILE *out = fopen(argv[2], "wb");
            if (out) {
                fwrite(out_buf, 1, out_len, out);
                fclose(out);
            }
            free(out_buf);
            fclose(in);
            return 0;
        }

        if (type == 0x01 || type == 0x02 || type == 0x03) {
            uint16_t len;
            if (fread(&len, 2, 1, in) != 1) {
                fprintf(stderr, "ERROR: Unexpected end of file\n");
                fclose(in);
                fclose(out_mem);
                free(out_buf);
                return 2;
            }

            char *payload = malloc(len + 1);
            if (len > 0) {
                if (fread(payload, 1, len, in) != len) {
                    fprintf(stderr, "ERROR: Unexpected end of file\n");
                    free(payload);
                    fclose(in);
                    fclose(out_mem);
                    free(out_buf);
                    return 2;
                }
            }
            payload[len] = '\0';

            if (type == 0x01) {
                fprintf(out_mem, "# %s\n\n", payload);
            } else if (type == 0x02) {
                fprintf(out_mem, "%s\n\n", payload);
            } else if (type == 0x03) {
                if (render_hidden) {
                    fprintf(out_mem, "<!-- %s -->\n\n", payload);
                }
            }
            free(payload);
        } else {
            fprintf(stderr, "ERROR: Unknown record type %u\n", type);
            fclose(in);
            fclose(out_mem);
            free(out_buf);
            return 3;
        }
    }
    return 0;
}
EOF

gcc -O2 /app/doc_compiler.c -o /app/doc_compiler
strip /app/doc_compiler
rm /app/doc_compiler.c

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/compiler_config.ini
[Settings]
render_hidden=true
EOF

chmod -R 777 /home/user
