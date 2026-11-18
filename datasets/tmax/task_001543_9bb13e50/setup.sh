#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb strace ffmpeg
    pip3 install pytest

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    # Create oracle C source
    cat << 'EOF' > /app/oracle_decoder.c
#include <stdio.h>
#include <stdint.h>

int main() {
    uint8_t buf[4096];
    size_t n = fread(buf, 1, 4096, stdin);
    if (n != 4096) return 1;
    if (buf[0] == 0xDE && buf[1] == 0xAD && buf[2] == 0xBE && buf[3] == 0xEF) {
        int sum = 0;
        for (int i = 4; i < 4096; i++) {
            sum += buf[i];
        }
        printf("%d\n", sum);
        return 0;
    }
    return 1;
}
EOF
    gcc -O3 /app/oracle_decoder.c -o /app/oracle_decoder
    rm /app/oracle_decoder.c

    # Create buggy C source
    cat << 'EOF' > /home/user/frame_decoder.c
#include <stdio.h>
#include <stdint.h>
#include <pthread.h>
#include <stdlib.h>

uint8_t buf[4096];
int error_flag = 0;
int global_sum = 0;
pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

void* worker(void* arg) {
    int id = *(int*)arg;
    int start = 4 + id * 1023;
    int end = start + 1023;

    if (buf[0] != 0xDE || buf[1] != 0xAD || buf[2] != 0xBE || buf[3] != 0xEF) {
        // Deliberate race condition
        error_flag = 1;
        return NULL;
    }

    int local_sum = 0;
    for (int i = start; i < end; i++) {
        local_sum += buf[i];
    }

    pthread_mutex_lock(&lock);
    global_sum += local_sum;
    pthread_mutex_unlock(&lock);

    return NULL;
}

int main() {
    size_t n = fread(buf, 1, 4096, stdin);
    if (n != 4096) return 1;

    pthread_t threads[4];
    int ids[4] = {0, 1, 2, 3};

    for (int i = 0; i < 4; i++) {
        pthread_create(&threads[i], NULL, worker, &ids[i]);
    }

    for (int i = 0; i < 4; i++) {
        pthread_join(threads[i], NULL);
    }

    if (error_flag) {
        // Crash to simulate the bug
        int *p = NULL;
        *p = 0;
        return 1;
    }

    printf("%d\n", global_sum);
    return 0;
}
EOF

    # Generate video
    cat << 'EOF' > /app/gen_video.py
import os
import random

total_frames = 120
corrupted_frames = 14
valid_frames = 106
expected_sum = 582390

frames = []
for i in range(corrupted_frames):
    frame = bytearray(random.getrandbits(8) for _ in range(4096))
    frame[0] = 0x00 # ensure corrupted
    frames.append(frame)

for i in range(valid_frames):
    frame = bytearray([0] * 4096)
    frame[0:4] = b'\xDE\xAD\xBE\xEF'
    frames.append(frame)

remaining_sum = expected_sum
for i in range(valid_frames):
    if i == valid_frames - 1:
        sum_for_this = remaining_sum
    else:
        sum_for_this = remaining_sum // (valid_frames - i)

    remaining_sum -= sum_for_this

    for j in range(4, 4096):
        val = min(255, sum_for_this)
        frames[corrupted_frames + i][j] = val
        sum_for_this -= val

random.seed(42)
random.shuffle(frames)

with open("/app/raw.yuv", "wb") as f:
    for frame in frames:
        f.write(frame)
EOF
    python3 /app/gen_video.py
    ffmpeg -y -f rawvideo -pix_fmt gray -s 64x64 -i /app/raw.yuv -c:v libx264 -crf 0 -preset ultrafast /app/profiling_target.mp4
    rm /app/raw.yuv /app/gen_video.py

    chmod -R 777 /home/user
