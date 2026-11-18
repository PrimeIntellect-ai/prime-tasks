#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make
    pip3 install pytest opencv-python-headless flask flask-limiter fastapi uvicorn

    mkdir -p /app

    # Generate the video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

width, height = 320, 240
fps = 10
out = cv2.VideoWriter('/app/build_metrics.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))

colors = {
    'red': (0, 0, 255),
    'green': (0, 255, 0),
    'blue': (255, 0, 0),
    'yellow': (0, 255, 255),
    'white': (255, 255, 255),
    'black': (0, 0, 0),
    'cyan': (255, 255, 0),
    'gray': (128, 128, 128)
}

# Exp 0: (11+1)*111
# Exp 1: 11111-11
sequence = [
    'white', 'yellow', 'yellow', 'red', 'yellow', 'black', 'blue', 'yellow', 'yellow', 'yellow', 'cyan',
    'gray', 'gray', 'gray',
    'yellow', 'yellow', 'yellow', 'yellow', 'yellow', 'green', 'yellow', 'yellow', 'cyan'
]

for color_name in sequence:
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    frame[:] = colors[color_name]
    out.write(frame)

    # Insert a gray frame between symbols to make it realistic
    frame_gray = np.zeros((height, width, 3), dtype=np.uint8)
    frame_gray[:] = colors['gray']
    out.write(frame_gray)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/matheval

    cat << 'EOF' > /home/user/matheval/evaluate.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Buggy evaluate function
int evaluate_expression(const char* expr) {
    char stack[10]; // Bug: Buffer overflow
    strcpy(stack, expr);

    // Simple dummy implementation for the sake of the bug
    int result = 0;
    // ... actual parsing logic would go here ...

    char* temp = malloc(10);
    strcpy(temp, "done");
    free(temp); // Bug: use after free if we were to return temp, but returning int

    return result;
}
EOF

    cat << 'EOF' > /home/user/matheval/Makefile
CC = gcc
CFLAGS = -fPIC -Wall
LDFLAGS = -shared

all: libmatheval.so

libmatheval.so: evaluate.o
	$(CC) $(LDFLAGS) -o libmatheval.so evaluate.o -lmath # Bug: -lmath instead of -lm

evaluate.o: evaluate.c
	$(CC) $(CFLAGS) -c evaluate.c

clean:
	rm -f *.o *.so
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
