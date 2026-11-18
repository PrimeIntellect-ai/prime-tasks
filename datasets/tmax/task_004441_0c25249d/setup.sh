#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate the diagnostic recording wav file
    cat << 'EOF' > /tmp/gen_wav.py
import wave
import struct
import math

sample_rate = 44100
duration = 10
frequency = 440
dc_offset = 15000

with wave.open('/app/diagnostic_recording.wav', 'w') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)

    for i in range(sample_rate * duration):
        value = int(math.sin(2 * math.pi * frequency * i / sample_rate) * 10000 + dc_offset)
        value = max(-32768, min(32767, value))
        wav_file.writeframes(struct.pack('<h', value))
EOF
    python3 /tmp/gen_wav.py
    rm /tmp/gen_wav.py

    # Create the buggy C file
    cat << 'EOF' > /home/user/audio_analyzer.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char header[32];
    if (fread(header, 1, 32, f) != 32) return 1;

    uint32_t length = *(uint32_t*)(header + 4);

    int16_t *data = malloc(length * sizeof(int16_t));
    if (!data) {
        fclose(f);
        return 1;
    }

    fread(data, sizeof(int16_t), length, f);

    float sum = 0;
    float sum_sq = 0;
    for (uint32_t i = 0; i < length; i++) {
        sum += data[i];
        sum_sq += (float)data[i] * data[i];
    }

    float mean = sum / length;
    float variance = sum_sq / length - mean * mean;
    float rms = sqrt(sum_sq / length);

    printf("RMS: %.6f\n", rms);
    printf("Variance: %.6f\n", variance);

    free(data);
    fclose(f);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
