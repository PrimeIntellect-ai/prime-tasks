#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest numpy scipy

    mkdir -p /home/user/src
    mkdir -p /app

    cat << 'EOF' > /home/user/src/audio_filter.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

// Simple WAV header structure
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

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("Usage: %s <input.wav> <output.wav>\n", argv[0]);
        return 1;
    }
    FILE *fin = fopen(argv[1], "rb");
    FILE *fout = fopen(argv[2], "wb");
    if (!fin || !fout) return 1;

    WavHeader header;
    fread(&header, sizeof(WavHeader), 1, fin);
    fwrite(&header, sizeof(WavHeader), 1, fout);

    int num_samples = header.data_size / sizeof(int16_t);
    int16_t *in = malloc(num_samples * sizeof(int16_t));
    int16_t *out = malloc(num_samples * sizeof(int16_t));

    fread(in, sizeof(int16_t), num_samples, fin);

    // Bug: out-of-bounds access for i=0 and i=1
    for (int i = 0; i < num_samples; i++) {
        out[i] = (in[i] + in[i-1] + in[i-2]) / 3;
    }

    fwrite(out, sizeof(int16_t), num_samples, fout);

    free(in);
    free(out);
    fclose(fin);
    fclose(fout);
    return 0;
}
EOF

    # Generate a dummy WAV file
    python3 -c "
import scipy.io.wavfile as wav
import numpy as np

rate = 44100
duration = 2.0
t = np.linspace(0, duration, int(rate * duration), endpoint=False)
data = (np.sin(2 * np.pi * 440 * t) * 10000).astype(np.int16)
wav.write('/app/test_speech.wav', rate, data)
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
