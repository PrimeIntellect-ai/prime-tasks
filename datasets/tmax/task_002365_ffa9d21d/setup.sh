#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
pip3 install pytest

mkdir -p /app/log-query-1.0
mkdir -p /hidden

cat << 'EOF' > /app/log-query-1.0/main.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <string.h>

void* dummy(void* arg) { return NULL; }

int main(int argc, char** argv) {
    pthread_t t;
    pthread_create(&t, NULL, dummy, NULL);
    pthread_join(t, NULL);

    char* key = getenv("AUTH_KEY");
    if (!key) { printf("Missing AUTH_KEY\n"); return 1; }

    #ifndef DATA_DIR
    #define DATA_DIR "/var/log/"
    #endif

    if (strcmp(DATA_DIR, "/var/log/") != 0) {
        printf("Wrong DATA_DIR: %s\n", DATA_DIR);
        return 1;
    }

    if (argc > 2 && strcmp(argv[1], "parse") == 0) {
        printf("Timeline parsed successfully.\n");
    }

    return 0;
}
EOF

cat << 'EOF' > /app/log-query-1.0/Makefile
CC=gcc
CFLAGS=-O2 -DDATA_DIR=\"/var/wrong/path\"
LDFLAGS=

log-query: main.c
	$(CC) $(CFLAGS) main.c -o log-query $(LDFLAGS)
EOF

dd if=/dev/urandom of=/app/authd.core bs=1M count=1 2>/dev/null
echo -n "AUTHKEY-9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d" >> /app/authd.core
dd if=/dev/urandom bs=1M count=1 >> /app/authd.core 2>/dev/null

echo -n "[AUDIT] 2023-10-27T03:01:00 User root login failed" > /tmp/audit1.txt
echo "" >> /tmp/audit1.txt
dd if=/dev/urandom of=/app/logs_partition.img bs=1M count=1 2>/dev/null
cat /tmp/audit1.txt >> /app/logs_partition.img
dd if=/dev/urandom bs=1M count=1 >> /app/logs_partition.img 2>/dev/null

cat << 'EOF' > /app/recover_logs.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    FILE* f = fopen(argv[1], "rb");
    FILE* out = fopen(argv[2], "wb");
    if (!f || !out) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char* data = malloc(size);
    fread(data, 1, size, f);

    for (long i = 0; i < size; i++) {
        if (i + 7 < size && memcmp(data + i, "[AUDIT]", 7) == 0) {
            long j = i;
            while (j < size && data[j] != '\n') j++;
            fwrite(data + i, 1, j - i + 1, out);
            i = j;
        }
    }

    free(data);
    fclose(f);
    fclose(out);
    return 0;
}
EOF

python3 -c "
import os
with open('/hidden/expected.log', 'wb') as f_exp, open('/hidden/large_partition.img', 'wb') as f_img:
    chunk = b'\x00' * (1024*1024)
    for i in range(500):
        f_img.write(chunk)
        if i % 100 == 0:
            log = f'[AUDIT] Log entry {i}\n'.encode()
            f_img.write(log)
            f_exp.write(log)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
chmod -R 755 /hidden
