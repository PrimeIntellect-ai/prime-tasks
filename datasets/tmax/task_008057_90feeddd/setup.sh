#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

mkdir -p /home/user/forensics_tool
mkdir -p /home/user/data

cat << 'EOF' > /home/user/forensics_tool/decoder.h
#ifndef DECODER_H
#define DECODER_H

#include <stdint.h>
#include <stddef.h>

struct EvidenceHeader {
    uint16_t magic;
    uint32_t payload_len;
};

int find_sync_offset(const uint8_t* data, int size);
void extract_payload(const uint8_t* data, int start_offset, int len, char* out);

#endif
EOF

cat << 'EOF' > /home/user/forensics_tool/decoder.c
#include "decoder.h"

int find_sync_offset(const uint8_t* data, int size) {
    int left = 0;
    int right = size - 1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (data[mid] == 0xFF) {
            return mid + 1;
        }
        if (data[mid] < 0xFF) {
            left = mid;
        } else {
            right = mid;
        }
    }
    return -1;
}

void extract_payload(const uint8_t* data, int start_offset, int len, char* out) {
    for (int i = 0; i <= len; i++) {
        out[i] = data[start_offset + i] ^ 0x42;
    }
    out[len] = '\0';
}
EOF

cat << 'EOF' > /home/user/forensics_tool/main.c
#include <stdio.h>
#include <stdlib.h>
#include "decoder.h"

int main(int argc, char** argv) {
    if (argc < 2) return 1;

    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t* buffer = malloc(size);
    fread(buffer, 1, size, f);
    fclose(f);

    struct EvidenceHeader* hdr = (struct EvidenceHeader*)buffer;
    if (hdr->magic != 0x5A5A) {
        printf("Invalid magic: %x\n", hdr->magic);
        return 1;
    }

    int sync = find_sync_offset(buffer + sizeof(struct EvidenceHeader), size - sizeof(struct EvidenceHeader));
    if (sync == -1) {
        printf("Sync failed\n");
        return 1;
    }

    int actual_start = sizeof(struct EvidenceHeader) + sync;
    char* output = malloc(hdr->payload_len + 1);
    extract_payload(buffer, actual_start, hdr->payload_len, output);

    printf("%s\n", output);
    free(output);
    free(buffer);
    return 0;
}
EOF

cat << 'EOF' > /home/user/forensics_tool/Makefile
CC = gcc
CFLAGS = -Wall -g

carver: main.o
	$(CC) $(CFLAGS) -o carver main.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

decoder.o: decoder.c
	$(CC) $(CFLAGS) -c decoder.c

clean:
	rm -f *.o carver
EOF

python3 -c "
import struct
magic = 0x5A5A
payload = b'FLAG{F0r3ns1cs_M4st3r_X0R}'
payload_len = len(payload)
header = struct.pack('<HL', magic, payload_len)
sync_data = bytes([0x10, 0x20, 0x30, 0xFF])
encoded_payload = bytes([b ^ 0x42 for b in payload])
trailing_garbage = bytes([0x77])
with open('/home/user/data/evidence.bin', 'wb') as f:
    f.write(header + sync_data + encoded_payload + trailing_garbage)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
