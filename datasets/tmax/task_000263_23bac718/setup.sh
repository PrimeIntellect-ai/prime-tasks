#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go ffmpeg
    pip3 install pytest

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/meta-extractor
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil
    mkdir -p /app

    # Generate files using Python
    python3 -c "
import os
import random
import struct

# Create meta-extractor main.go
with open('/home/user/meta-extractor/main.go', 'w') as f:
    f.write('''package main

import (
\t\"fmt\"
\t\"time\"
)

func main() {
\tvar timestamp int32 = int32(time.Now().UnixNano() & 0xFFFFFFFF) // To simulate precision loss error, but wait, the prompt says: 'var timestamp int32 = time.Now().UnixNano()'
\t// Let's use exactly what the prompt says
}
''')

with open('/home/user/meta-extractor/main.go', 'w') as f:
    f.write('''package main

import (
\t\"fmt\"
\t\"time\"
)

func main() {
\tvar timestamp int32 = time.Now().UnixNano()
\tdata := []byte{1, 2, 3}
\tfor i := 0; i <= len(data); i++ {
\t\tfmt.Println(data[i])
\t}
\tfmt.Println(timestamp)
}
''')

# Create corpus
header = b'\x4D\x45\x54\x41'
for i in range(50):
    with open(f'/home/user/corpus/clean/clean_{i}.bin', 'wb') as f:
        f.write(header + struct.pack('>h', 10))
    with open(f'/home/user/corpus/evil/evil_{i}.bin', 'wb') as f:
        f.write(header + struct.pack('>h', -10))

# Create video raw frames
black_frame = b'\x00\x00\x00' * (64 * 64)
red_frame = b'\xFF\x00\x00' * (64 * 64)

frames = [black_frame] * 450
red_indices = random.sample(range(450), 7)
for idx in red_indices:
    frames[idx] = red_frame

with open('/tmp/raw.bin', 'wb') as f:
    for frame in frames:
        f.write(frame)
"

    # Compile raw video to mp4
    ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size 64x64 -framerate 30 -i /tmp/raw.bin -c:v libx264 -pix_fmt yuv444p -crf 0 /app/evidence.mp4
    rm /tmp/raw.bin

    chmod -R 777 /home/user
    chmod -R 777 /app
