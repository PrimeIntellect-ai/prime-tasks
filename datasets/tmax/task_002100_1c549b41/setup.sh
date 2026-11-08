#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential xxd ltrace strace
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/dataset
    mkdir -p /home/user/output

    # Create the C script for the vulnerable unpacker
    cat << 'EOF' > /app/unpacker.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

void create_dirs(const char *dir) {
    char tmp[256];
    char *p = NULL;
    size_t len;

    snprintf(tmp, sizeof(tmp), "%s", dir);
    len = strlen(tmp);
    if(tmp[len - 1] == '/')
        tmp[len - 1] = 0;
    for(p = tmp + 1; *p; p++)
        if(*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    mkdir(tmp, 0755);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <archive.parc>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        perror("fopen");
        return 1;
    }

    char magic[4];
    if (fread(magic, 1, 4, f) != 4 || strncmp(magic, "PRJC", 4) != 0) {
        printf("Invalid magic\n");
        fclose(f);
        return 1;
    }

    uint32_t num_files;
    if (fread(&num_files, 4, 1, f) != 1) {
        printf("Failed to read num_files\n");
        fclose(f);
        return 1;
    }

    for (uint32_t i = 0; i < num_files; i++) {
        uint16_t name_len;
        if (fread(&name_len, 2, 1, f) != 1) break;

        char *name = malloc(name_len + 1);
        if (fread(name, 1, name_len, f) != name_len) {
            free(name);
            break;
        }
        name[name_len] = '\0';

        uint32_t comp_size;
        if (fread(&comp_size, 4, 1, f) != 1) {
            free(name);
            break;
        }

        uint8_t *comp_data = malloc(comp_size);
        if (fread(comp_data, 1, comp_size, f) != comp_size) {
            free(comp_data);
            free(name);
            break;
        }

        // Vulnerable path extraction (Zip-Slip)
        char *last_slash = strrchr(name, '/');
        if (last_slash) {
            *last_slash = '\0';
            create_dirs(name);
            *last_slash = '/';
        }

        FILE *out = fopen(name, "wb");
        if (out) {
            for (uint32_t j = 0; j < comp_size; j += 2) {
                uint8_t count = comp_data[j];
                uint8_t byte = comp_data[j+1];
                for (uint8_t k = 0; k < count; k++) {
                    fputc(byte, out);
                }
            }
            fclose(out);
        }

        free(comp_data);
        free(name);
    }

    fclose(f);
    return 0;
}
EOF

    # Compile and strip the unpacker
    gcc -O2 /app/unpacker.c -o /app/unpacker
    strip /app/unpacker
    rm /app/unpacker.c

    # Generate the dataset
    cat << 'EOF' > /app/generate_dataset.py
import struct
import os
import random

def rle_encode(data):
    encoded = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i] == data[i+count] and count < 255:
            count += 1
        encoded.append(count)
        encoded.append(data[i])
        i += count
    return encoded

def create_parc(filename, files):
    with open(filename, 'wb') as f:
        f.write(b'PRJC')
        f.write(struct.pack('<I', len(files)))
        for name, data in files:
            name_bytes = name.encode('ascii')
            f.write(struct.pack('<H', len(name_bytes)))
            f.write(name_bytes)
            comp_data = rle_encode(data)
            f.write(struct.pack('<I', len(comp_data)))
            f.write(comp_data)

random.seed(42)
all_files = []
# Generate 2500 unique files
for i in range(2500):
    basename = f"file_{i}.txt"
    # Introduce zip-slip paths
    if random.random() < 0.2:
        path = f"../../etc/fake_{i}/" + basename
    elif random.random() < 0.4:
        path = f"nested/../../../home/user/fake_{i}/" + basename
    else:
        path = f"normal_dir/" + basename

    # Generate compressible data
    char = bytes([random.randint(65, 90)])
    data = char * random.randint(100, 50000)
    all_files.append((path, data))

random.shuffle(all_files)

archives = [[] for _ in range(1000)]
for i, f in enumerate(all_files):
    archives[i % 1000].append(f)

for i in range(1000):
    create_parc(f"/home/user/dataset/archive_{i}.parc", archives[i])

EOF

    python3 /app/generate_dataset.py
    rm /app/generate_dataset.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
