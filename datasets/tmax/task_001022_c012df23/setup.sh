#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/service

    # Generate the audio fixture
    python3 -c "
import wave, struct, math
with wave.open('/app/incident_809.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(44100)
    for i in range(44100 * 2):
        val = int(10000 * math.sin(2 * math.pi * 440 * i / 44100))
        f.writeframes(struct.pack('<h', val))
"

    # Create audio_ops.cpp with the out-of-bounds bug
    cat << 'EOF' > /home/user/service/audio_ops.cpp
#include <iostream>
#include <cmath>

extern "C" {
    double calculate_anomaly_score(short* data, int num_samples) {
        double sum_squares = 0.0;
        // BUG: Out of bounds read causing segfault
        for(int i = 0; i <= num_samples; i++) {
            sum_squares += (double)data[i] * (double)data[i];
        }
        return sqrt(sum_squares / num_samples);
    }
}
EOF

    # Create build.sh with the missing -lm flag
    cat << 'EOF' > /home/user/service/build.sh
#!/bin/bash
g++ -fPIC -shared -o libaudio.so audio_ops.cpp
EOF
    chmod +x /home/user/service/build.sh

    # Create pipeline.py
    cat << 'EOF' > /home/user/service/pipeline.py
import ctypes
import sys
import wave
import struct
import os

if len(sys.argv) < 2:
    print("Usage: python pipeline.py <wav_file>")
    sys.exit(1)

wav_path = sys.argv[1]

# Load library
lib_path = os.path.join(os.path.dirname(__file__), 'libaudio.so')
try:
    lib = ctypes.CDLL(lib_path)
except Exception as e:
    print(f"Failed to load library: {e}")
    sys.exit(1)

lib.calculate_anomaly_score.argtypes = [ctypes.POINTER(ctypes.c_short), ctypes.c_int]
lib.calculate_anomaly_score.restype = ctypes.c_double

with wave.open(wav_path, 'rb') as f:
    num_samples = f.getnframes()
    data = f.readframes(num_samples)

short_array = struct.unpack(f'<{num_samples}h', data)
c_array = (ctypes.c_short * num_samples)(*short_array)

score = lib.calculate_anomaly_score(c_array, num_samples)

with open(os.path.join(os.path.dirname(__file__), 'anomaly_score.txt'), 'w') as f:
    f.write(f"{score}\n")
print("Anomaly score generated.")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
