#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest numpy scipy

    mkdir -p /app

    # Create test signal
    cat << 'EOF' > /tmp/make_signal.py
import numpy as np
import scipy.io.wavfile as wav

sample_rate = 44100
t = np.linspace(0, 1, sample_rate, endpoint=False)
signal = np.sin(2 * np.pi * 440 * t)
wav.write("/app/test_signal.wav", sample_rate, signal.astype(np.float32))
EOF
    python3 /tmp/make_signal.py

    # Create core dump
    cat << 'EOF' > /tmp/make_core.py
with open("/app/dsp_crash.core", "wb") as f:
    f.write(b"\x00" * 1024)
    f.write(b"_INIT_SALT=X7k9P2mN4vR1wQ8z")
    f.write(b"\x00" * 1024)
EOF
    python3 /tmp/make_core.py

    # Setup repo
    mkdir -p /home/user/audio_dsp/src
    cd /home/user/audio_dsp
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > src/filters.py
import numpy as np

def apply_filter(x):
    y = np.zeros_like(x, dtype=np.float64)
    y[0] = x[0]
    for n in range(1, len(x)):
        y[n] = 0.99 * y[n-1] + x[n]
    return y
EOF

    cat << 'EOF' > src/pipeline.py
import numpy as np
from scipy.io import wavfile
from .filters import apply_filter

class DSPPipeline:
    def __init__(self, salt):
        self.salt = salt
        np.random.seed(sum(ord(c) for c in salt))

    def process(self, wav_path):
        sr, data = wavfile.read(wav_path)
        data = data.astype(np.float64) + np.random.normal(0, 0.01, size=data.shape)
        filtered = apply_filter(data)
        return filtered
EOF

    touch __init__.py src/__init__.py
    git add .
    git commit -m "Initial commit"
    git tag v1.0-good

    # Generate ground truth
    cat << 'EOF' > /tmp/gen_truth.py
import numpy as np
import sys
sys.path.insert(0, "/home/user/audio_dsp")
from src.pipeline import DSPPipeline

pipeline = DSPPipeline("X7k9P2mN4vR1wQ8z")
res = pipeline.process("/app/test_signal.wav")
np.save("/app/ground_truth_fingerprint.npy", res)
EOF
    python3 /tmp/gen_truth.py

    # Add commits up to 65
    for i in $(seq 1 65); do
        echo "# $i" >> src/__init__.py
        git commit -am "Commit $i"
    done

    # Commit 66 (Bug)
    cat << 'EOF' > src/filters.py
import numpy as np

def apply_filter(x):
    y = np.zeros_like(x, dtype=np.float32)
    y[0] = x[0]
    n = 1
    while n < len(x):
        val = np.float32(0.99) * y[n-1] + np.float32(x[n])
        if val == y[n-1]:
            continue # infinite loop bug
        y[n] = val
        n += 1
    return y
EOF
    git commit -am "Refactor filter to recursive implementation"

    # Add commits up to 200
    for i in $(seq 67 200); do
        echo "# $i" >> src/__init__.py
        git commit -am "Commit $i"
    done

    git tag v1.1-bad

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
