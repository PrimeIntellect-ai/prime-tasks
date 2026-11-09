#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest numpy scipy

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_wav.py
import numpy as np
from scipy.io import wavfile
import os

sr = 44100
duration = 300 # 5 minutes
samples = np.random.randn(sr * duration).astype(np.float32)
samples = np.int16(samples / np.max(np.abs(samples)) * 32767)
wavfile.write('/app/sample.wav', sr, samples)
EOF
    python3 /tmp/gen_wav.py
    rm /tmp/gen_wav.py

    mkdir -p /home/user/pr_workspace

    cat << 'EOF' > /home/user/pr_workspace/rms.c
#include <math.h>

void compute_rms(const float* input, int num_samples, int window_size, float* output) {
    for (int i = 0; i < num_samples; i++) {
        int start = i - window_size / 2;
        int end = i + window_size / 2;
        if (start < 0) start = 0;
        if (end > num_samples - 1) end = num_samples - 1;

        float sum_sq = 0.0f;
        int count = end - start + 1;
        for (int j = start; j <= end; j++) {
            sum_sq += input[j] * input[j];
        }
        output[i] = sqrtf(sum_sq / count);
    }
}
EOF

    cat << 'EOF' > /home/user/pr_workspace/Makefile
all:
	gcc -o librms.so rms.c
EOF

    cat << 'EOF' > /home/user/pr_workspace/wrapper.py
import ctypes
import numpy as np
import os

lib = ctypes.CDLL(os.path.join(os.path.dirname(__file__), 'librms.so'))

# Incorrect argtypes
lib.compute_rms.argtypes = [
    ctypes.POINTER(ctypes.c_double),
    ctypes.c_int,
    ctypes.c_int,
    ctypes.POINTER(ctypes.c_double)
]

def compute_rms_c(input_array, window_size):
    input_array = np.ascontiguousarray(input_array, dtype=np.float32)
    output_array = np.zeros_like(input_array, dtype=np.float32)

    lib.compute_rms(
        input_array.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
        len(input_array),
        window_size,
        output_array.ctypes.data_as(ctypes.POINTER(ctypes.c_double))
    )
    return output_array
EOF

    cat << 'EOF' > /home/user/pr_workspace/benchmark.py
import sys
import time
import numpy as np
from scipy.io import wavfile
from wrapper import compute_rms_c

def compute_rms_py(input_array, window_size):
    sq = input_array ** 2
    output = np.zeros_like(input_array)
    for i in range(len(input_array)):
        start = max(0, i - window_size // 2)
        end = min(len(input_array) - 1, i + window_size // 2)
        output[i] = np.sqrt(np.mean(sq[start:end+1]))
    return output

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python benchmark.py <wav_file>")
        sys.exit(1)

    sr, data = wavfile.read(sys.argv[1])
    if data.dtype != np.float32:
        data = data.astype(np.float32) / 32768.0

    data = data[:10000]

    window_size = 1024

    t0 = time.perf_counter()
    ref = compute_rms_py(data, window_size)
    t1 = time.perf_counter()
    print(f"Python time: {t1-t0:.4f}s")

    t0 = time.perf_counter()
    out = compute_rms_c(data, window_size)
    t1 = time.perf_counter()
    print(f"C time: {t1-t0:.4f}s")

    mse = np.mean((ref - out)**2)
    print(f"MSE: {mse}")
    assert mse < 1e-5, "MSE too high"
    print("Success!")
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
