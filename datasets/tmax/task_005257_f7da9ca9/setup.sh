#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make gcc gawk
    pip3 install pytest numpy

    mkdir -p /app/c_port

    # Create Python reference implementation
    cat << 'EOF' > /app/processor.py
import sys
import wave
import struct

def process(wav_path, out_path):
    with wave.open(wav_path, 'rb') as w:
        frames = w.readframes(w.getnframes())
        samples = struct.unpack(f"<{len(frames)//2}h", frames)

    window_size = 256
    threshold = 100000000.0

    results = []
    for i in range(0, len(samples), window_size):
        window = samples[i:i+window_size]
        if len(window) < window_size:
            break
        energy = sum(s*s for s in window)
        if energy > threshold:
            results.append(0.0)
        else:
            results.append(float(energy))

    with open(out_path, 'w') as f:
        for r in results:
            f.write(f"{r}\n")

if __name__ == '__main__':
    process(sys.argv[1], sys.argv[2])
EOF

    # Generate test WAV file
    cat << 'EOF' > /tmp/gen_wav.py
import wave
import struct
import random

with wave.open('/app/recording.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(16000)
    samples = [int(random.gauss(0, 2000)) for _ in range(16000 * 5)]
    w.writeframes(struct.pack(f"<{len(samples)}h", *samples))
EOF
    python3 /tmp/gen_wav.py

    # Create broken Makefile
    cat << 'EOF' > /app/c_port/Makefile
ste_processor: main.o ste.o
gcc -o ste_processor main.o ste.o

main.o: main.c
gcc -c main.c

ste.o: ste.c
gcc -c ste.c
EOF

    # Create broken main.c
    cat << 'EOF' > /app/c_port/main.c
#include <stdio.h>
#include <stdlib.h>

void process(const char* in, const char* out);

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    process(argv[1], argv[2]);
    return 0;
}
EOF

    # Create broken ste.c
    cat << 'EOF' > /app/c_port/ste.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

void process(const char* in_path, const char* out_path) {
    FILE* in = fopen(in_path, "rb");
    FILE* out = fopen(out_path, "w");
    fseek(in, 44, SEEK_SET);

    int16_t window[256]
    while (fread(window, sizeof(int16_t), 256, in) == 256) {
        double energy = 0;
        for (int i=0; i<256; i++) {
            energy += window[i] * window[i];
        }
        if (energy > 100000000.0) {
            fprintf(out, "0.0\n");
        } else {
            fprintf(out, "%f\n", energy);
        }
    }
    fclose(in);
    fclose(out);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
