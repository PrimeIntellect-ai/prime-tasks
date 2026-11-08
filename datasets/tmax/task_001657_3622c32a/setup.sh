#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/log_analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#pragma pack(push, 1)
struct EventHeader {
    uint32_t magic; // 0x45564E54
    uint16_t type;
    uint16_t length;
};
#pragma pack(pop)

int process_event(struct EventHeader* header, FILE* f) {
    char buffer[64];
    if (header->type == 1) {
        fread(buffer, 1, header->length, f);
        // BUG: Stack buffer overflow / Out of bounds write if length >= 64
        buffer[header->length] = '\0'; 
        return header->length;
    } else {
        fseek(f, header->length, SEEK_CUR);
        return 0;
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <file>\n", argv[0]);
        return 1;
    }
    FILE* f = fopen(argv[1], "rb");
    if (!f) {
        printf("Cannot open file\n");
        return 1;
    }

    struct EventHeader header;
    int count = 0;
    long long type1_sum = 0;

    while (fread(&header, sizeof(header), 1, f) == 1) {
        if (header.magic != 0x45564E54) {
            printf("Invalid magic at event %d\n", count);
            break;
        }
        type1_sum += process_event(&header, f);
        count++;
    }

    printf("Processed %d events, Type1 length sum: %lld\n", count, type1_sum);
    fclose(f);
    return 0;
}
EOF

    python3 -c '
import struct

def make_event(ev_type, length):
    magic = 0x45564E54
    header = struct.pack("<IHH", magic, ev_type, length)
    payload = b"A" * length
    return header + payload

with open("/home/user/data/event_log.bin", "wb") as f:
    f.write(make_event(1, 10))
    f.write(make_event(2, 5))
    f.write(make_event(1, 64))
    f.write(make_event(1, 100))
    f.write(make_event(2, 20))
    f.write(make_event(1, 42))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
