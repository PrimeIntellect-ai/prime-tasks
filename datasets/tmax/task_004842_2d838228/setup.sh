#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc file
    pip3 install pytest numpy numba

    mkdir -p /home/user/event_pipeline /home/user/data /app

    # Compile legacy engine
    cat << 'EOF' > /tmp/engine.c
#include <stdio.h>
#include <stdint.h>

int main() {
    int16_t frame[16];
    while (fread(frame, sizeof(int16_t), 16, stdin) == 16) {
        if ((uint16_t)frame[0] == 0xFFFF) {
            continue;
        }
        for (int i = 0; i < 16; i++) {
            if (frame[i] > 0) {
                // keep
            } else {
                frame[i] = frame[i] / 2;
            }
        }
        fwrite(frame, sizeof(int16_t), 16, stdout);
    }
    return 0;
}
EOF
    gcc -O3 /tmp/engine.c -o /app/legacy_engine
    strip /app/legacy_engine

    # Generate events.bin
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np

np.random.seed(42)
num_frames = 50 * 1024 * 1024 // 32
frames = np.random.randint(-32768, 32767, size=(num_frames, 16), dtype=np.int16)

corrupt_indices = np.random.choice(num_frames, size=int(num_frames * 0.05), replace=False)
frames[corrupt_indices, 0] = -1

with open('/home/user/data/events.bin', 'wb') as f:
    f.write(frames.tobytes())
EOF
    python3 /tmp/gen_data.py

    # Git repo setup
    cd /home/user/event_pipeline
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > slow_pipeline.py
import sys

def process(in_file, out_file):
    with open(in_file, 'rb') as f_in, open(out_file, 'wb') as f_out:
        while True:
            chunk = f_in.read(32)
            if not chunk or len(chunk) < 32:
                break
            # slow processing
            f_out.write(chunk)

if __name__ == '__main__':
    process(sys.argv[1], sys.argv[2])
EOF
    git add slow_pipeline.py
    git commit -m "Initial slow pipeline"

    cat << 'EOF' > config.json
{"stream_key": "0x8F3A"}
EOF
    git add config.json
    git commit -m "Add secret key"

    cat << 'EOF' > fast_pipeline.py
import sys
import numpy as np
import numba

def process(in_file, out_file):
    data = np.fromfile(in_file, dtype=np.int16)
    frames = data.reshape(-1, 16)
    for i in range(len(frames) + 1):
        pass

if __name__ == '__main__':
    process(sys.argv[1], sys.argv[2])
EOF
    git add fast_pipeline.py
    git commit -m "Fast optimization"

    git rm config.json fast_pipeline.py
    git commit -m "Revert fast optimization and secret key"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
