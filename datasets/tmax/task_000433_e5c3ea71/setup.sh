#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/src

    cat << 'EOF' > /app/src/legacy_filter.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int cap = 100;
    int *arr = malloc(cap * sizeof(int));
    int n = 0;
    while (scanf("%d", &arr[n]) == 1) {
        n++;
        if (n >= cap) {
            cap *= 2;
            arr = realloc(arr, cap * sizeof(int));
        }
    }

    if (n == 0) return 0;

    // Inefficient Rolling max-min (Window = 5)
    for (int i = 0; i < n; i++) {
        int min_val = arr[i];
        int max_val = arr[i];
        for (int j = i - 2; j <= i + 2; j++) {
            int idx = j;
            if (idx < 0) idx = 0;
            if (idx >= n) idx = n - 1;

            if (arr[idx] < min_val) min_val = arr[idx];
            if (arr[idx] > max_val) max_val = arr[idx];
        }
        printf("%d", max_val - min_val);
        if (i < n - 1) printf(" ");
    }
    printf("\n");
    free(arr);
    return 0;
}
EOF

    cat << 'EOF' > /app/oracle_filter.py
import sys

def main():
    input_data = sys.stdin.read().split()
    if not input_data:
        return
    arr = [int(x) for x in input_data]
    n = len(arr)
    out = []
    for i in range(n):
        window = []
        for j in range(i - 2, i + 3):
            idx = max(0, min(n - 1, j))
            window.append(arr[idx])
        out.append(str(max(window) - min(window)))
    print(" ".join(out))

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import math

out = cv2.VideoWriter('/app/telemetry_trace.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30.0, (640, 480))
for t in range(120):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    x = int(320 + 200 * math.sin(0.1 * t))
    y = 240
    if 0 <= x < 640:
        frame[y, x] = (255, 255, 255)
    out.write(frame)
out.release()
EOF

    python3 /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
