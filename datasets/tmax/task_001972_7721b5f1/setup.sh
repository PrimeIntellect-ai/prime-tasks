#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install --default-timeout=100 pytest scipy numpy

cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
from scipy.io import wavfile
import random

os.makedirs('/app/src', exist_ok=True)
os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)
os.makedirs('/app/build', exist_ok=True)

# Generate signal.wav
sample_rate = 44100
t = np.linspace(0, 1, sample_rate, False)
tone1 = np.sin(440 * 2 * np.pi * t)
tone2 = np.sin(880 * 2 * np.pi * t)
tone3 = np.sin(1320 * 2 * np.pi * t)
signal = np.concatenate((tone1, tone2, tone3))
wavfile.write('/app/signal.wav', sample_rate, signal.astype(np.float32))

# Generate artifact_parser.cpp
cpp_code = """#include <iostream>
#include <cstring>
#include <cstdlib>

extern "C" {
    int parse_artifact(const char* data, int length) {
        int MAGIC_1 = __MAGIC_1__;
        int MAGIC_2 = __MAGIC_2__;
        int MAX_BUF = __MAX_BUF__;

        char* buffer = (char*)malloc(length + 1);
        strcpy(buffer, data);

        return 0;
    }
}
"""
with open('/app/src/artifact_parser.cpp', 'w') as f:
    f.write(cpp_code)

# Generate clean corpus
for i in range(50):
    with open(f'/app/corpora/clean/file_{i}.txt', 'w') as f:
        f.write("440\n880\n" + "A" * random.randint(10, 100))

# Generate evil corpus
for i in range(25):
    with open(f'/app/corpora/evil/large_{i}.txt', 'w') as f:
        f.write("440\n880\n" + "A" * 1500)
for i in range(15):
    with open(f'/app/corpora/evil/exec_{i}.txt', 'w') as f:
        f.write("440\n880\n" + "EXEC_PAYLOAD")
for i in range(10):
    with open(f'/app/corpora/evil/magic_{i}.txt', 'w') as f:
        f.write("441\n880\n" + "A" * 50)
EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
