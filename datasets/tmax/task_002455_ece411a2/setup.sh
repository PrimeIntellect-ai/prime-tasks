#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /app
mkdir -p /home/user

# Create the legacy C binary source
cat << 'EOF' > /app/legacy_detector.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    // Skip 44-byte WAV header
    fseek(f, 44, SEEK_SET);

    fseek(f, 0, SEEK_END);
    long size = ftell(f) - 44;
    fseek(f, 44, SEEK_SET);

    if (size < 0) size = 0;
    int num_samples = size / 2;
    int16_t *samples = malloc(num_samples * sizeof(int16_t));
    if (num_samples > 0) {
        fread(samples, sizeof(int16_t), num_samples, f);
    }
    fclose(f);

    int window_size = 256;
    int step_size = 128;
    for (int i = 0; i <= num_samples - window_size; i += step_size) {
        long long energy = 0;
        for (int j = 0; j < window_size; j++) {
            int16_t s = samples[i + j];
            int32_t shifted = s >> 4;
            energy += (shifted * shifted);
        }
        printf("%lld ", energy);
    }
    printf("\n");
    free(samples);
    return 0;
}
EOF

# Compile the C binary
gcc -O3 -o /app/legacy_detector /app/legacy_detector.c
rm /app/legacy_detector.c

# Create the buggy Python script
cat << 'EOF' > /home/user/detector.py
import sys
import wave

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    with wave.open(sys.argv[1], 'rb') as w:
        frames = w.readframes(w.getnframes())

    samples = []
    for i in range(0, len(frames), 2):
        s = int.from_bytes(frames[i:i+2], byteorder='little', signed=True)
        samples.append(s)

    window_size = 256
    step_size = 127 # BUG: should be 128

    out = []
    i = 0
    while i <= len(samples) - window_size:
        energy = 0.0
        for j in range(window_size):
            s = samples[i + j]
            # BUG: float math instead of bitshift
            val = s / 16.0
            energy += val * val
        out.append(str(int(energy)))
        i += step_size

    print(" ".join(out))

if __name__ == '__main__':
    main()
EOF

# Create a Python script to generate the sample audio WAV file
cat << 'EOF' > /tmp/gen_audio.py
import wave
import struct
import random

with wave.open('/app/sample_audio.wav', 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(8000)
    for _ in range(20000):
        val = random.randint(-32768, 32767)
        w.writeframes(struct.pack('<h', val))
EOF

python3 /tmp/gen_audio.py
rm /tmp/gen_audio.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
