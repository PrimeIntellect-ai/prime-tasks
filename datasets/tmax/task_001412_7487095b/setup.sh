#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg netcat-openbsd socat gawk
    pip3 install pytest

    mkdir -p /app
    mkdir -p /tmp/frames

    cat << 'EOF' > /tmp/gen.py
import os

def create_pgm(filename, tl, tr, bl, br):
    with open(filename, 'w') as f:
        f.write("P2\n100 100\n255\n")
        for y in range(100):
            row = []
            for x in range(100):
                if y < 50:
                    val = tl if x < 50 else tr
                else:
                    val = bl if x < 50 else br

                if isinstance(val, float) and val != int(val):
                    base = int(val)
                    row.append(str(base + ((x+y)%2)))
                else:
                    row.append(str(int(val)))
            f.write(" ".join(row) + "\n")

frames = [
    (10, 20, 30, 40),
    (200, 100, 50, 10),
    (150, 150, 150, 150),
    (0, 255, 0, 255),
    (110, 60, 90, 180),
    (120, 50, 80, 200),
    (120.5, 49.0, 81.5, 199.0),
    (120.5, 49.0, 81.5, 199.0),
    (120.5, 49.0, 81.5, 199.0),
    (120.5, 49.0, 81.5, 199.0),
]

for i, f in enumerate(frames):
    create_pgm(f'/tmp/frames/frame_{i+1:03d}.pgm', *f)
EOF

    python3 /tmp/gen.py
    ffmpeg -framerate 1 -i /tmp/frames/frame_%03d.pgm -c:v libx264 -pix_fmt yuv420p /app/microarray_timelapse.mp4
    rm -rf /tmp/frames /tmp/gen.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
