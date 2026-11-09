#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron curl
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/stream_gen.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc != 2 || strcmp(argv[1], "--start-stream-0x4A") != 0) {
        return 1;
    }
    const char *tags[] = {"正常", "エラー", "警告", "успех", "ошибка"};
    int num_tags = 5;

    setvbuf(stdout, NULL, _IONBF, 0);
    srand(time(NULL));

    while (1) {
        long current_time = (long)time(NULL);
        const char *tag = tags[rand() % num_tags];
        float val = (float)(rand() % 10000) / 100.0;
        printf("%ld|%s|%.2f\n", current_time, tag, val);
        usleep(100000);
    }
    return 0;
}
EOF

    gcc -O2 /app/stream_gen.c -o /app/stream_gen
    strip /app/stream_gen
    rm /app/stream_gen.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
