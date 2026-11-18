#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/dsp_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

// Simple WAV header parsing (assumes perfectly formatted 32-bit float mono for the test)
#pragma pack(push, 1)
typedef struct {
    char riff_header[4];
    int32_t wav_size;
    char wave_header[4];
    char fmt_header[4];
    int32_t fmt_chunk_size;
    int16_t audio_format;
    int16_t num_channels;
    int32_t sample_rate;
    int32_t byte_rate;
    int16_t sample_alignment;
    int16_t bit_depth;
    char data_header[4];
    int32_t data_bytes;
} WavHeader;
#pragma pack(pop)

void process_audio(float* data, int num_samples) {
    float y_prev = 0.0f;
    float alpha = 0.999f; // high feedback causing slow decay into denormals

    for (int i = 0; i < num_samples; i++) {
        // Recursive IIR filter
        y_prev = (data[i] * (1.0f - alpha)) + (y_prev * alpha);
        data[i] = y_prev;
    }
}

int main(int argc, char** argv) {
    if (argc < 3) {
        printf("Usage: %s <in.wav> <out.wav>\n", argv[0]);
        return 1;
    }

    FILE* in = fopen(argv[1], "rb");
    FILE* out = fopen(argv[2], "wb");
    if (!in || !out) return 1;

    WavHeader header;
    fread(&header, sizeof(WavHeader), 1, in);

    int num_samples = header.data_bytes / sizeof(float);
    float* buffer = (float*)malloc(header.data_bytes);

    fread(buffer, sizeof(float), num_samples, in);

    process_audio(buffer, num_samples);

    fwrite(&header, sizeof(WavHeader), 1, out);
    fwrite(buffer, sizeof(float), num_samples, out);

    fclose(in);
    fclose(out);
    free(buffer);

    return 0;
}
EOF

    cat << 'EOF' > /tmp/generate_wav.py
import struct

def generate_wav(filename):
    sample_rate = 44100
    duration = 30
    num_samples = sample_rate * duration

    with open(filename, 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + num_samples * 4))
        f.write(b'WAVE')
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))
        f.write(struct.pack('<H', 3))
        f.write(struct.pack('<H', 1))
        f.write(struct.pack('<I', sample_rate))
        f.write(struct.pack('<I', sample_rate * 4))
        f.write(struct.pack('<H', 4))
        f.write(struct.pack('<H', 32))
        f.write(b'data')
        f.write(struct.pack('<I', num_samples * 4))

        f.write(struct.pack('<f', 1.0))
        zero_bytes = struct.pack('<f', 0.0) * (num_samples - 1)
        f.write(zero_bytes)

generate_wav('/app/suspicious_audio.wav')
EOF

    python3 /tmp/generate_wav.py
    rm /tmp/generate_wav.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
