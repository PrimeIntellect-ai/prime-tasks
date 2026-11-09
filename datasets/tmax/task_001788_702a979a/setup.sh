#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/xpak_pack.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

uint32_t crc32(const unsigned char *buf, size_t len) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= buf[i];
        for (int j = 0; j < 8; j++) {
            if (crc & 1)
                crc = (crc >> 1) ^ 0xEDB88320;
            else
                crc >>= 1;
        }
    }
    return crc ^ 0xFFFFFFFF;
}

struct FileEntry {
    char *filename;
    uint8_t name_len;
    uint32_t uncomp_size;
    uint32_t comp_size;
    uint32_t crc;
    unsigned char *comp_data;
};

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char *out_filename = argv[1];
    int num_files = argc - 2;
    if (num_files < 0) num_files = 0;
    if (num_files > 65535) num_files = 65535;

    struct FileEntry *entries = calloc(num_files, sizeof(struct FileEntry));

    for (int i = 0; i < num_files; i++) {
        char *in_filename = argv[i + 2];
        FILE *f = fopen(in_filename, "rb");
        if (!f) continue;

        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        fseek(f, 0, SEEK_SET);

        unsigned char *uncomp = malloc(size);
        if (size > 0) fread(uncomp, 1, size, f);
        fclose(f);

        entries[i].filename = in_filename;
        entries[i].name_len = strlen(in_filename) > 255 ? 255 : strlen(in_filename);
        entries[i].uncomp_size = size;
        entries[i].crc = crc32(uncomp, size);

        unsigned char *comp = malloc(size * 2 + 1);
        uint32_t comp_size = 0;
        if (size > 0) {
            uint32_t pos = 0;
            while (pos < size) {
                unsigned char c = uncomp[pos];
                uint8_t count = 1;
                while (pos + count < size && count < 255 && uncomp[pos + count] == c) {
                    count++;
                }
                comp[comp_size++] = count;
                comp[comp_size++] = c;
                pos += count;
            }
        }
        entries[i].comp_data = comp;
        entries[i].comp_size = comp_size;
        free(uncomp);
    }

    FILE *out = fopen(out_filename, "wb");
    if (!out) return 1;

    fwrite("XPAK", 1, 4, out);
    uint16_t nf = num_files;
    fwrite(&nf, 2, 1, out);

    for (int i = 0; i < num_files; i++) {
        fwrite(&entries[i].name_len, 1, 1, out);
        fwrite(entries[i].filename, 1, entries[i].name_len, out);
        fwrite(&entries[i].uncomp_size, 4, 1, out);
        fwrite(&entries[i].comp_size, 4, 1, out);
        fwrite(&entries[i].crc, 4, 1, out);
    }

    for (int i = 0; i < num_files; i++) {
        if (entries[i].comp_size > 0) {
            fwrite(entries[i].comp_data, 1, entries[i].comp_size, out);
        }
    }
    fclose(out);

    char manifest_name[1024];
    snprintf(manifest_name, sizeof(manifest_name), "%s.manifest", out_filename);
    FILE *man = fopen(manifest_name, "w");
    if (man) {
        for (int i = 0; i < num_files; i++) {
            fprintf(man, "%s,%u,%08x\n", entries[i].filename, entries[i].uncomp_size, entries[i].crc);
        }
        fclose(man);
    }

    return 0;
}
EOF

    gcc -O2 /tmp/xpak_pack.c -o /app/xpak_pack
    strip /app/xpak_pack
    chmod +x /app/xpak_pack

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
