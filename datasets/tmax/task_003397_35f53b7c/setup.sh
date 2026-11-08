#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg python3-opencv python3-numpy
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/diagnostic.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 24, (100, 100))
# Create 120 frames total. 14 of them will be purely green.
for i in range(120):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if i % 8 == 0 and i < 112: # 112 / 8 = 14 frames
        frame[:, :] = [0, 255, 0] # BGR format: purely green
    else:
        frame[:, :] = [50, 50, 50] # Gray
    out.write(frame)
out.release()
EOF
    python3 /app/generate_video.py

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/normalize_oracle.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#define N 14

void convert_utf16le_to_utf8(const uint8_t *in, size_t in_len, uint8_t *out, size_t *out_len) {
    size_t o = 0;
    for (size_t i = 0; i + 1 < in_len; i += 2) {
        uint16_t cp = in[i] | (in[i+1] << 8);
        if (cp <= 0x007F) {
            out[o++] = (uint8_t)cp;
        } else if (cp <= 0x07FF) {
            out[o++] = 0xC0 | (cp >> 6);
            out[o++] = 0x80 | (cp & 0x3F);
        } else {
            // Basic BMP only for simplicity, avoiding surrogates for this mock
            out[o++] = 0xE0 | (cp >> 12);
            out[o++] = 0x80 | ((cp >> 6) & 0x3F);
            out[o++] = 0x80 | (cp & 0x3F);
        }
    }
    *out_len = o;
}

int main() {
    uint8_t buf[64];
    size_t read_bytes = fread(buf, 1, 64, stdin);
    if (read_bytes < 64) {
        memset(buf + read_bytes, 0, 64 - read_bytes);
    }

    if (memcmp(buf, "\x7F" "ELF", 4) == 0) {
        uint16_t e_type = buf[0x10] | (buf[0x11] << 8);
        uint16_t e_machine = buf[0x12] | (buf[0x13] << 8);
        uint64_t e_entry = 0;
        for (int i = 0; i < 8; i++) {
            e_entry |= ((uint64_t)buf[0x18 + i]) << (i * 8);
        }
        printf("ELF %04x %04x %016lx\n", e_type, e_machine, e_entry + N);
    } else if (memcmp(buf, "WAL\x00", 4) == 0) {
        uint32_t salt = buf[8] | (buf[9] << 8) | (buf[10] << 16) | (buf[11] << 24);
        printf("WAL %08x\n", salt ^ N);
    } else {
        uint8_t utf8_out[128];
        size_t utf8_len = 0;
        convert_utf16le_to_utf8(buf, 64, utf8_out, &utf8_len);

        size_t limit = (utf8_len < N) ? utf8_len : N;
        for (size_t i = 0; i < limit; i++) {
            if (utf8_out[i] < 0x20 || utf8_out[i] > 0x7E) {
                putchar('.');
            } else {
                putchar(utf8_out[i]);
            }
        }
        putchar('\n');
    }

    return 0;
}
EOF
    gcc /opt/oracle/normalize_oracle.c -o /opt/oracle/normalize_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
