#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential gcc
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/audio_tool

    # Create diagnostic recording
    python3 -c "
import struct
with open('/app/diagnostic_recording.wav', 'wb') as f:
    # Dummy WAV header
    f.write(b'RIFF\x00\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00')
    meta_data = b'DIAG-7729-ALPHA'
    encoded = bytes([b ^ 0x8F for b in meta_data])
    f.write(b'META' + struct.pack('<I', len(encoded)) + encoded)
"

    # Setup git repo
    cd /home/user/audio_tool
    git init
    git config user.name "Admin"
    git config user.email "admin@example.com"

    # Commit 1: Working version
    cat << 'EOF' > process_audio.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#define SECRET_KEY 0x8F

pthread_mutex_t lock1 = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_t lock2 = PTHREAD_MUTEX_INITIALIZER;

void process_chunk(unsigned char* data, int size) {
    pthread_mutex_lock(&lock1);
    pthread_mutex_lock(&lock2);
    for(int i=0; i<size; i++) {
        data[i] ^= SECRET_KEY;
    }
    pthread_mutex_unlock(&lock2);
    pthread_mutex_unlock(&lock1);
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char* buf = malloc(size);
    if (!buf) return 1;
    fread(buf, 1, size, f);
    fclose(f);

    for(long i=0; i<size-8; i++) {
        if(buf[i] == 'M' && buf[i+1] == 'E' && buf[i+2] == 'T' && buf[i+3] == 'A') {
            int meta_size = *(int*)(&buf[i+4]);
            if (i + 8 + meta_size <= size) {
                process_chunk(&buf[i+8], meta_size);
                printf("%.*s\n", meta_size, &buf[i+8]);
            }
            break;
        }
    }
    free(buf);
    return 0;
}
EOF
    gcc -O2 process_audio.c -o /app/oracle_audio_tool -lpthread
    strip /app/oracle_audio_tool
    git add process_audio.c
    git commit -m "Initial working version"

    # Commit 2: Deadlock
    sed -i 's/pthread_mutex_lock(&lock2);/pthread_mutex_unlock(&lock1); pthread_mutex_lock(&lock2); pthread_mutex_lock(&lock1);/' process_audio.c
    git add process_audio.c
    git commit -m "Refactor concurrency"

    # Commit 3: Off-by-one buffer overflow
    sed -i 's/for(int i=0; i<size; i++)/for(int i=0; i<=size; i++)/' process_audio.c
    git add process_audio.c
    git commit -m "Update chunking"

    # Commit 4: Remove secret
    sed -i 's/#define SECRET_KEY 0x8F/#define SECRET_KEY 0x00 \/\/ TODO: implement secure key exchange/' process_audio.c
    git add process_audio.c
    git commit -m "Remove hardcoded secret"

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
