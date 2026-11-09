#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make libgl1 libglib2.0-0
    pip3 install pytest opencv-python numpy

    mkdir -p /home/user/libjit
    cat << 'EOF' > /home/user/libjit/jit_compiler.c
int add_pixels(int a, int b) {
    return a + b;
}
EOF

    cat << 'EOF' > /home/user/libjit/Makefile
all: libjit.so

libjit.so: jit_compiler.o
	gcc -o libjit.so jit_compiler.o

jit_compiler.o: jit_compiler.c
	gcc -c jit_compiler.c

clean:
	rm -f *.o *.so
EOF

    mkdir -p /app/corpus/clean /app/corpus/evil

    echo '{"payload": "90909090c3"}' > /app/corpus/clean/1.json
    echo '{"payload": "4889f84801d0c3"}' > /app/corpus/clean/2.json
    echo '{"payload": "48c7c001000000"}' > /app/corpus/clean/3.json

    echo '{"payload": "b801000000bf010000000f05"}' > /app/corpus/evil/1.json
    echo '{"payload": "9090cd8090"}' > /app/corpus/evil/2.json
    echo '{"payload": "0f34c3"}' > /app/corpus/evil/3.json

    python3 -c '
import cv2
import numpy as np

width, height = 320, 240
fps = 10
out = cv2.VideoWriter("/app/ci_run.mp4", cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))

for i in range(60):
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    if i in [12, 25, 48]:
        frame[0, 0] = [0, 0, 255] # BGR format for OpenCV, so pure red
    out.write(frame)

out.release()
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
