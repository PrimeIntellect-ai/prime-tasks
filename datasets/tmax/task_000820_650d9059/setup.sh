#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make coreutils libc6-dev
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/data
    mkdir -p /home/user/src
    mkdir -p /app

    # Create logs
    cat << 'EOF' > /home/user/logs/svc1.log
[2023-10-24T12:00:01Z] INFO chunk_id=1001 processing_time=12ms
[2023-10-24T12:00:02Z] INFO chunk_id=1002 processing_time=14ms
EOF
    cat << 'EOF' > /home/user/logs/svc2.log
[2023-10-24T12:00:03Z] INFO chunk_id=8923 processing_time=12ms
[2023-10-24T12:00:05Z] INFO chunk_id=9402 processing_time=5102ms
EOF
    cat << 'EOF' > /home/user/logs/svc3.log
[2023-10-24T12:00:06Z] INFO chunk_id=9403 processing_time=15ms
EOF

    # Create raw payloads data
    head -c 200000 /dev/urandom > /home/user/data/raw_payloads.bin

    # Create legacy processor
    cat << 'EOF' > /app/legacy_processor.c
#include <stdio.h>
#include <unistd.h>

int main() {
    int c;
    int count = 0;
    while ((c = fgetc(stdin)) != EOF) {
        printf("%02X", (unsigned char)(c ^ 0x5A));
        count++;
        if (count % 1000 == 0) {
            usleep(10000); // Artificial sluggishness
        }
    }
    return 0;
}
EOF
    gcc -O3 /app/legacy_processor.c -o /app/legacy_processor
    strip /app/legacy_processor
    rm /app/legacy_processor.c

    # Create broken fast processor
    cat << 'EOF' > /home/user/src/fast_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    int c;
    char *buffer = malloc(1000000);
    if (!buffer) return 1;
    buffer[0] = '\0';
    char temp[3];
    double dummy = sin(0.0); 

    while ((c = fgetc(stdin)) != EOF) {
        unsigned char val = (unsigned char)(c ^ 0x5B); 
        assert(val >= 0); 
        sprintf(temp, "%02X", val);
        strcat(buffer, temp); 
    }
    printf("%s", buffer);
    free(buffer);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
