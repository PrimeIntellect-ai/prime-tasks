#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sqlite3 ffmpeg libsm6 libxext6 libgl1-mesa-glx
    pip3 install pytest fastapi uvicorn opencv-python

    mkdir -p /home/user/mathlib /home/user/db /app

    cat << 'EOF' > /home/user/mathlib/mathops.c
#include <math.h>

double compute_max_variation(double* values, int length, int window_size) {
    if (length < window_size) return 0.0;
    double max_std_dev = -1.0;

    for (int i = 0; i <= length - window_size; i++) {
        double sum = 0.0;
        for (int j = 0; j < window_size; j++) {
            sum += values[i + j];
        }
        double mean = sum / window_size;

        double variance_sum = 0.0;
        for (int j = 0; j < window_size; j++) {
            variance_sum += pow(values[i + j] - mean, 2);
        }
        double std_dev = sqrt(variance_sum / window_size);

        if (std_dev > max_std_dev) {
            max_std_dev = std_dev;
        }
    }
    return max_std_dev;
}
EOF

    cat << 'EOF' > /home/user/mathlib/Makefile
libmathops.so: mathops.c
	gcc -shared -fPIC mathops.c -o libmathops.so
EOF

    sqlite3 /home/user/db/metrics.db "CREATE TABLE video_stats (id INTEGER PRIMARY KEY, filename TEXT);"

    # Generate a dummy video file
    ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=10 -pix_fmt yuv420p /app/video.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
