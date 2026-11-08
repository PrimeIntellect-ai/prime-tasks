#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo gcc g++ make
    pip3 install pytest fastapi uvicorn numpy scipy

    mkdir -p /app/wav_parser/src
    mkdir -p /app/c_filter
    mkdir -p /app/cpp_core
    mkdir -p /app/api

    cat << 'EOF' > /app/wav_parser/Cargo.toml
[package]
name = "wav_parser"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /app/wav_parser/src/lib.rs
#[repr(C)]
pub struct WavHeader { pub channels: u16, pub sample_rate: u32 }

#[no_mangle]
pub extern "C" fn parse_header(data: *const u8, len: usize) -> *mut WavHeader {
    let mut header = WavHeader { channels: 1, sample_rate: 8000 };
    &mut header as *mut WavHeader
}
EOF

    cat << 'EOF' > /app/c_filter/Makefile
CC=gcc
CFLAGS=-Wall -O2

libfilter.so: filter.o
	$(CC) -shared -o libfilter.so filter.o

filter.o: filter.c
	$(CC) $(CFLAGS) -c filter.c
EOF

    cat << 'EOF' > /app/c_filter/filter.c
#include <stddef.h>

void moving_average(const float* input, float* output, size_t length, size_t window) {
    for (size_t i = 0; i < length; i++) {
        float sum = 0;
        size_t count = 0;
        for (size_t j = 0; j < window; j++) {
            if (i >= j) {
                sum += input[i - j];
                count++;
            }
        }
        output[i] = sum / count;
    }
}
EOF

    cat << 'EOF' > /app/api/server.py
from fastapi import FastAPI

app = FastAPI()

@app.post("/process")
def process_audio(file_path: str):
    return {"status": "unimplemented"}
EOF

    python3 -c "
import numpy as np
import scipy.io.wavfile as wav
sample_rate = 8000
duration = 180
samples = np.random.uniform(-1, 1, sample_rate * duration).astype(np.float32)
wav.write('/app/fixture_audio.wav', sample_rate, samples)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
