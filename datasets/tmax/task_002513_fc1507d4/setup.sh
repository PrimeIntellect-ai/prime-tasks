#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app
    mkdir -p /home/user/audio_math

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import scipy.io.wavfile as wavfile
import json

sample_rate = 16000
duration = 5.0
t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
signal = 0.5 * np.sin(2 * np.pi * 440 * t) + 0.2 * np.sin(2 * np.pi * 1000 * t)
signal = signal * np.exp(-t/2)
wavfile.write('/app/test_signal.wav', sample_rate, signal.astype(np.float32))

chunk_size = 2048
expected_energies = []
for i in range(0, len(signal), chunk_size):
    chunk = signal[i:i+chunk_size]
    energy = np.sum(chunk ** 2) / len(chunk)
    expected_energies.append(float(energy))

with open('/home/user/expected_reference.json', 'w') as f:
    json.dump(expected_energies, f)

broken_code = """import sys
import os
import json
import numpy as np
import scipy.io.wavfile as wavfile
from multiprocessing import Pool

class BadEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, float):
            return float(f"{obj:.2f}")
        return super().default(obj)

def compute_energy(chunk_data):
    # Bug 2: precision loss
    chunk_f16 = chunk_data.astype(np.float16)
    energy = np.sum(chunk_f16 ** 2) / len(chunk_f16)
    return float(energy)

def process_file(filepath):
    rate, data = wavfile.read(filepath)
    chunk_size = 2048
    chunks = []
    for i in range(0, len(data), chunk_size):
        chunks.append(data[i:i+chunk_size])

    # Bug 1: imap_unordered causes race condition / ordering loss
    results = []
    with Pool(4) as p:
        for res in p.imap_unordered(compute_energy, chunks):
            results.append(res)

    # Bug 3: serialization loss
    with open('/home/user/fixed_output.json', 'w') as f:
        json.dump(results, f, cls=BadEncoder)

if __name__ == '__main__':
    process_file('/app/test_signal.wav')
"""

with open('/home/user/audio_math/pipeline.py', 'w') as f:
    f.write(broken_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
