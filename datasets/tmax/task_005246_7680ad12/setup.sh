#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libfftw3-dev
    pip3 install pytest numpy scipy flask requests

    mkdir -p /app/src/spectral
    mkdir -p /app/bin

    cat << 'EOF' > /app/src/spectral/main.cpp
#include <iostream>
#include <fftw3.h>

int main() {
    fftw_complex *in, *out;
    fftw_plan p;
    int N = 10;
    in = (fftw_complex*) fftw_malloc(sizeof(fftw_complex) * N);
    out = (fftw_complex*) fftw_malloc(sizeof(fftw_complex) * N);
    p = fftw_plan_dft_1d(N, in, out, FFTW_FORWARD, FFTW_ESTIMATE);
    fftw_execute(p);
    fftw_destroy_plan(p);
    fftw_free(in); 
    fftw_free(out);
    return 0;
}
EOF

    cat << 'EOF' > /app/src/spectral/Makefile
all:
	mkdir -p /app/bin
	g++ main.cpp -lfftw3 -o /app/bin/spectral_extractor
EOF

    cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
import scipy.io.wavfile as wav

fs = 16000
t = np.linspace(0, 5, fs * 5, endpoint=False)
audio = np.random.randn(len(t)) * 0.1
audio += np.sin(2 * np.pi * 440 * t) * 0.5
# 1s silent gap
audio[fs*2:fs*3] = 0.0
wav.write('/app/machinery_audio.wav', fs, audio.astype(np.float32))
EOF

    python3 /tmp/generate_audio.py
    rm /tmp/generate_audio.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
