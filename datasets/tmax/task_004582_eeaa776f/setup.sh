#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo
    pip3 install pytest

    mkdir -p /app /home/user

    # Create C source for legacy tracker
    cat << 'EOF' > /tmp/legacy_tracker.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/stat.h>

typedef struct {
    uint64_t ts;
    uint8_t op;
    uint16_t path_len;
    char* path;
    uint32_t payload_len;
    uint8_t* payload;
} Record;

int compare_records(const void* a, const void* b) {
    Record* ra = *(Record**)a;
    Record* rb = *(Record**)b;
    if (ra->ts < rb->ts) return -1;
    if (ra->ts > rb->ts) return 1;
    return 0;
}

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    DIR* d = opendir(argv[1]);
    if (!d) return 1;
    struct dirent* dir;
    Record** records = malloc(20000 * sizeof(Record*));
    int count = 0;
    while ((dir = readdir(d)) != NULL) {
        if (strstr(dir->d_name, ".wal")) {
            char filepath[1024];
            snprintf(filepath, sizeof(filepath), "%s/%s", argv[1], dir->d_name);
            FILE* f = fopen(filepath, "rb");
            if (!f) continue;
            while (!feof(f)) {
                Record* r = malloc(sizeof(Record));
                if (fread(&r->ts, 8, 1, f) != 1) { free(r); break; }
                if (fread(&r->op, 1, 1, f) != 1) { free(r); break; }
                if (fread(&r->path_len, 2, 1, f) != 1) { free(r); break; }
                r->path = malloc(r->path_len + 1);
                if (fread(r->path, 1, r->path_len, f) != r->path_len) { free(r->path); free(r); break; }
                r->path[r->path_len] = 0;
                if (fread(&r->payload_len, 4, 1, f) != 1) { free(r->path); free(r); break; }
                r->payload = malloc(r->payload_len);
                if (fread(r->payload, 1, r->payload_len, f) != r->payload_len) { free(r->payload); free(r->path); free(r); break; }
                records[count++] = r;
            }
            fclose(f);
        }
    }
    closedir(d);
    qsort(records, count, sizeof(Record*), compare_records);

    mkdir(argv[2], 0777);
    for (int i = 0; i < count; i++) {
        Record* r = records[i];
        usleep(1000); // 1ms sleep to make it artificially slow
        char outpath[1024];
        snprintf(outpath, sizeof(outpath), "%s/%s", argv[2], r->path);

        char* ext = strstr(outpath, ".gcode_b");
        if (ext && strlen(ext) == 8) {
            *ext = 0;
            strcat(outpath, ".gcode");
            for (uint32_t j = 0; j < r->payload_len; j++) {
                r->payload[j] ^= 0x5A;
            }
        }

        if (r->op == 0) {
            remove(outpath);
        } else {
            FILE* out = fopen(outpath, "wb");
            if (out) {
                fwrite(r->payload, 1, r->payload_len, out);
                fclose(out);
            }
        }
    }
    return 0;
}
EOF

    # Compile and strip the legacy tracker
    gcc -O2 /tmp/legacy_tracker.c -o /app/legacy_tracker
    strip /app/legacy_tracker
    chmod +x /app/legacy_tracker

    # Generate WAL files
    cat << 'EOF' > /tmp/gen_wals.py
import struct
import os
import random

def write_wal(dir_path, num_files, records_per_file):
    os.makedirs(dir_path, exist_ok=True)
    ts = 1000
    for i in range(num_files):
        with open(os.path.join(dir_path, f"log_{i}.wal"), "wb") as f:
            for j in range(records_per_file):
                op = 1 # PUT
                path = f"file_{random.randint(0, 50)}.gcode_b".encode()
                payload = f"G01 X{random.randint(0,100)} Y{random.randint(0,100)}".encode()
                payload = bytes([b ^ 0x5A for b in payload])
                f.write(struct.pack("<QB H", ts, op, len(path)))
                f.write(path)
                f.write(struct.pack("<I", len(payload)))
                f.write(payload)
                ts += 1

write_wal("/home/user/sample_wals", 2, 10)
write_wal("/home/user/large_wals", 10, 1000)
EOF
    python3 /tmp/gen_wals.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
