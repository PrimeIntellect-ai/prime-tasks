#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang
    pip3 install pytest

    mkdir -p /app/extractor

    # Create the WAV file using Python
    cat << 'EOF' > /tmp/gen_wav.py
import wave
import struct
import math

sample_rate = 8000
duration_ms = 5500
peaks = [500, 1200, 2400, 3100, 4800]

out = wave.open('/app/signal.wav', 'w')
out.setnchannels(1)
out.setsampwidth(2)
out.setframerate(sample_rate)

for i in range(duration_ms):
    is_peak = False
    for p in peaks:
        if abs(i - p) < 15:
            is_peak = True
            break

    amp = 30000 if is_peak else 1000
    for j in range(sample_rate // 1000):
        val = int(amp * math.sin(2 * math.pi * 400 * (i * (sample_rate//1000) + j) / sample_rate))
        out.writeframesraw(struct.pack('<h', val))

out.close()
EOF
    python3 /tmp/gen_wav.py

    # Create broken C program
    cat << 'EOF' > /app/extractor/main.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
/* Missing #include <stdint.h> */

#pragma pack(push, 1)
struct WavHeader {
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
};
#pragma pack(pop)

int main(int argc, char** argv) {
    if (argc < 3) {
        printf("Usage: %s <input.wav> <output.bin>\n", argv[0]);
        return 1;
    }
    FILE* in = fopen(argv[1], "rb");
    if (!in) return 1;
    struct WavHeader header;
    fread(&header, sizeof(header), 1, in);

    FILE* out = fopen(argv[2], "wb");
    if (!out) return 1;

    int16_t sample;
    int count = 0;
    double sum_sq = 0;
    uint32_t time_ms = 0;

    while (fread(&sample, sizeof(int16_t), 1, in) == 1) {
        sum_sq += ((double)sample / 32768.0) * ((double)sample / 32768.0);
        count++;
        if (count == header.sample_rate / 1000) {
            float rms = (float)sqrt(sum_sq / count);
            fwrite(&time_ms, sizeof(uint32_t), 1, out);
            fwrite(&rms, sizeof(float), 1, out);
            time_ms++;
            count = 0;
            sum_sq = 0;
        }
    }

    fclose(in) /* Syntax error: missing semicolon */
    fclose(out);
    return 0;
}
EOF

    # Create broken Makefile
    cat << 'EOF' > /app/extractor/Makefile
all: extract_features

extract_features: main.c
gcc -o extract_features main.c -lm
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
