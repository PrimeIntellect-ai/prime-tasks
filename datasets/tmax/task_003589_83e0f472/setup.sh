#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import math
import random

os.makedirs('/app', exist_ok=True)

# 1. Create memory.core with hidden string
with open('/app/memory.core', 'wb') as f:
    f.write(os.urandom(1024))
    f.write(b"CALIB_KEY=A9F3B2C8E7D61540\x00")
    f.write(os.urandom(2048))

# 2. Create input.wav (16-bit mono, 8000Hz) with some synthetic noisy signal
sample_rate = 8000
num_samples = 8000 * 3 # 3 seconds
with open('/app/input.wav', 'wb') as f:
    # WAV Header
    f.write(b'RIFF')
    f.write(struct.pack('<I', 36 + num_samples * 2))
    f.write(b'WAVEfmt ')
    f.write(struct.pack('<I', 16))
    f.write(struct.pack('<HHIIHH', 1, 1, sample_rate, sample_rate * 2, 2, 16))
    f.write(b'data')
    f.write(struct.pack('<I', num_samples * 2))

    # Generate data: low freq sine + high amplitude noise that causes standard LMS to diverge
    for i in range(num_samples):
        val = math.sin(2 * math.pi * 400 * i / sample_rate) * 10000
        val += random.uniform(-15000, 15000)
        f.write(struct.pack('<h', int(val)))

# 3. Create nlms_filter.c
c_code = """
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#pragma pack(push, 1)
typedef struct {
    char riff[4];
    uint32_t overall_size;
    char wave[4];
    char fmt_chunk_marker[4];
    uint32_t length_of_fmt;
    uint16_t format_type;
    uint16_t channels;
    uint32_t sample_rate;
    uint32_t byterate;
    uint16_t block_align;
    uint16_t bits_per_sample;
    char data_chunk_header[4];
    uint32_t data_size;
} WavHeader;
#pragma pack(pop)

int main(int argc, char** argv) {
    if(argc != 4) {
        printf("Usage: %s <input.wav> <output.wav> <calib_key>\\n", argv[0]);
        return 1;
    }

    if (strncmp(argv[3], "A9F3B2C8E7D61540", 16) != 0) {
        printf("Invalid calibration key!\\n");
        return 1;
    }

    FILE* fin = fopen(argv[1], "rb");
    FILE* fout = fopen(argv[2], "wb");

    WavHeader header;
    fread(&header, sizeof(WavHeader), 1, fin);
    fwrite(&header, sizeof(WavHeader), 1, fout);

    int num_samples = header.data_size / 2;
    int16_t* input = (int16_t*)malloc(num_samples * 2);
    int16_t* output = (int16_t*)malloc(num_samples * 2);

    fread(input, 2, num_samples, fin);

    float mu = 0.5f; 
    float w = 0.0f;

    // BUG 1: Off-by-one error (i <= num_samples) causing heap buffer overflow
    for(int i = 0; i <= num_samples; i++) {
        float x = input[i] / 32768.0f;
        float d = 0.0f; 
        float y = w * x;
        float e = d - y;

        // BUG 2: Numerical instability. Needs NLMS
        w += mu * e * x; 

        float out_val = e * 32768.0f;
        if(out_val > 32767.0f) out_val = 32767.0f;
        if(out_val < -32768.0f) out_val = -32768.0f;
        output[i] = (int16_t)out_val;
    }

    fwrite(output, 2, num_samples, fout);
    fclose(fin);
    fclose(fout);
    free(input);
    free(output);
    return 0;
}
"""
with open('/app/nlms_filter.c', 'w') as f:
    f.write(c_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
