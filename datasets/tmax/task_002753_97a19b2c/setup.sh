#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/emitter.c
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

int main() {
    srand(42);
    long current_time = 1696118400; // 2023-10-01T00:00:00
    const char* actions[] = {"LOGIN", "DOWNLOAD", "UPLOAD", "LOGOUT"};

    char prev_log[256] = {0};
    int i;
    for(i=0; i<500000; i++) {
        int r = rand() % 100;
        if(r < 10 && i > 0) {
            // Duplicate (10%)
            printf("%s", prev_log);
            continue;
        }

        current_time += (rand() % 10) + 1;
        struct tm *tm_info = gmtime(&current_time);
        char time_buf[30];
        strftime(time_buf, 30, "%Y-%m-%dT%H:%M:%S", tm_info);

        int user_id = rand() % 50;
        const char* action = actions[rand() % 4];
        int bytes = 100 + (rand() % 4901);

        if(r >= 10 && r < 15) {
            // Malformed (5%)
            printf("%s user_%d %s src=10.0.0.1 %d\n", time_buf, user_id, action, bytes);
        } else {
            // Normal
            sprintf(prev_log, "[%s] user_%d %s src=10.0.0.1 bytes=%d\n", time_buf, user_id, action, bytes);
            printf("%s", prev_log);
        }
    }
    return 0;
}
EOF

gcc -O2 /app/emitter.c -o /app/log_emitter
strip /app/log_emitter
rm /app/emitter.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
