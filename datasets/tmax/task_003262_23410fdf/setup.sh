#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg make gcc
    pip3 install pytest

    mkdir -p /app/extractor

    # Create manifest.json
    cat << 'EOF' > /app/manifest.json
{"auth-service": "1.5.0", "billing": "2.0.0-alpha.1", "frontend": "3.1.4"}
EOF

    # Create broken Makefile (spaces instead of tabs)
    cat << 'EOF' > /app/extractor/Makefile
all:
        gcc -o decoder decoder.c
EOF

    # Create buggy decoder.c
    cat << 'EOF' > /app/extractor/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#pragma pack(push, 1)
typedef struct {
    uint16_t bfType;
    uint32_t bfSize;
    uint16_t bfReserved1;
    uint16_t bfReserved2;
    uint32_t bfOffBits;
} BITMAPFILEHEADER;

typedef struct {
    uint32_t biSize;
    int32_t  biWidth;
    int32_t  biHeight;
    uint16_t biPlanes;
    uint16_t biBitCount;
    uint32_t biCompression;
    uint32_t biSizeImage;
    int32_t  biXPelsPerMeter;
    int32_t  biYPelsPerMeter;
    uint32_t biClrUsed;
    uint32_t biClrImportant;
} BITMAPINFOHEADER;
#pragma pack(pop)

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    BITMAPFILEHEADER bfh;
    BITMAPINFOHEADER bih;
    fread(&bfh, sizeof(bfh), 1, f);
    fread(&bih, sizeof(bih), 1, f);

    fseek(f, bfh.bfOffBits, SEEK_SET);

    int width = bih.biWidth;
    int height = bih.biHeight;
    if (height < 0) height = -height;

    int row_size = ((width * bih.biBitCount + 31) / 32) * 4;

    // Bug: off-by-one array bounds leading to stack corruption / segfault
    uint8_t *rows[height];
    for (int i = 0; i <= height; i++) {
        rows[i] = malloc(row_size);
        fread(rows[i], 1, row_size, f);
    }

    char out[1024] = {0};
    int idx = 0;
    // The top row is the last row read (index height - 1)
    uint8_t *top_row = rows[height - 1];
    for (int i = 0; i < width; i++) {
        uint8_t r = top_row[i * 3 + 2];
        if (r == 0) break;
        out[idx++] = r;
    }

    if (idx > 0 && out[0] == '{') {
        printf("%s\n", out);
    }

    for (int i = 0; i < height; i++) free(rows[i]);
    fclose(f);
    return 0;
}
EOF

    # Python script to generate the video
    cat << 'EOF' > /tmp/gen_video.py
import os
import json

width, height = 320, 240
row_size = ((width * 24 + 31) // 32) * 4

telemetry_data = [
    {"component": "auth-service", "version": "1.4.2-beta"},
    {"component": "billing", "version": "2.0.0-alpha.2"},
    {"component": "frontend", "version": "3.1.3"}
]

os.makedirs("/tmp/frames", exist_ok=True)

def write_bmp(filename, data_str):
    with open(filename, "wb") as f:
        f.write(b'BM')
        filesize = 54 + row_size * height
        f.write(filesize.to_bytes(4, 'little'))
        f.write(b'\x00\x00\x00\x00')
        f.write((54).to_bytes(4, 'little'))

        f.write((40).to_bytes(4, 'little'))
        f.write(width.to_bytes(4, 'little'))
        f.write(height.to_bytes(4, 'little'))
        f.write((1).to_bytes(2, 'little'))
        f.write((24).to_bytes(2, 'little'))
        f.write((0).to_bytes(4, 'little'))
        f.write((row_size * height).to_bytes(4, 'little'))
        f.write((2835).to_bytes(4, 'little'))
        f.write((2835).to_bytes(4, 'little'))
        f.write((0).to_bytes(4, 'little'))
        f.write((0).to_bytes(4, 'little'))

        empty_row = b'\x00' * row_size
        for _ in range(height - 1):
            f.write(empty_row)

        top_row = bytearray(row_size)
        if data_str:
            b_str = data_str.encode('utf-8')
            for i, b in enumerate(b_str):
                top_row[i*3 + 2] = b
        f.write(top_row)

for i in range(60):
    data = ""
    if i % 3 == 0 and (i // 3) < len(telemetry_data):
        data = json.dumps(telemetry_data[i // 3])
    write_bmp(f"/tmp/frames/frame_{i:03d}.bmp", data)

os.system("ffmpeg -y -framerate 30 -i /tmp/frames/frame_%03d.bmp -c:v libx264rgb -crf 0 /app/deploy_capture.mp4")
EOF

    python3 /tmp/gen_video.py
    rm -rf /tmp/frames /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
