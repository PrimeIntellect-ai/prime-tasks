#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb e2fsprogs
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app
    mkdir -p /opt/legacy_libs

    # Generate video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

fps = 30
duration = 10
total_frames = fps * duration

out = cv2.VideoWriter('/app/incident_record.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (640, 480))
for i in range(total_frames):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    if i == 142:
        frame[:] = (0, 0, 255) # BGR
    else:
        frame[:] = (255, 255, 255)
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py

    # Create dummy library
    cat << 'EOF' > /tmp/custom_math.c
int custom_add(int a, int b) { return a + b; }
EOF
    gcc -shared -fPIC -o /opt/legacy_libs/libcustom_math.so /tmp/custom_math.c

    # Create source code
    cat << 'EOF' > /app/sync_tool.c
#include <stdio.h>
#include <stdlib.h>

extern int custom_add(int, int);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;

    int data[10000];
    int count = 0;
    while(fscanf(f, "%d", &data[count]) == 1) {
        if (data[count] < 0) {
            int idx = data[count];
            data[10000 + idx] = 0;
        }
        count++;
    }
    fclose(f);

    long long total_sum = 0;
    for(int i=0; i<count; i++) {
        long long sum = 0;
        for(int j=0; j<=i; j++) {
            sum = custom_add(sum, data[j]);
        }
        total_sum += sum;
    }
    printf("Total sum: %lld\n", total_sum);
    return 0;
}
EOF
    gcc -o /app/sync_tool /app/sync_tool.c -L/opt/legacy_libs -lcustom_math

    # Generate telemetry image
    mkdir -p /tmp/img_data
    cat << 'EOF' > /tmp/gen_data.py
with open("/tmp/img_data/run.dat", "w") as f:
    for i in range(300):
        if i == 142:
            f.write("-50000\n")
        else:
            f.write(f"{i}\n")
EOF
    python3 /tmp/gen_data.py

    dd if=/dev/zero of=/app/telemetry.img bs=1M count=10
    mkfs.ext4 -d /tmp/img_data /app/telemetry.img
    debugfs -w -R "rm run.dat" /app/telemetry.img

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
