#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc flite ffmpeg
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/pr_repo

    # Generate the audio file
    flite -t "Hey maintainer, sorry I forgot to commit this, but the initialization vector for the PR is zero x eight B A D F zero zero D. Thanks!" -o /app/pr_voice_note.wav

    # Create and compile the oracle binary
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdint.h>
int main() {
    uint32_t hash = 0x8BADF00D;
    int c;
    while ((c = getchar()) != EOF) {
        hash = (hash ^ (uint8_t)c) * 0x01000193;
    }
    printf("%08x\n", hash);
    return 0;
}
EOF
    gcc -O3 /app/oracle.c -o /app/oracle_bin
    strip /app/oracle_bin
    rm /app/oracle.c

    # Create the broken PR code
    cat << 'EOF' > /home/user/pr_repo/fasthash.c
#include <stdio.h>
#include <stdint.h>

int main() {
    // TODO: Maintainer, listen to the voice note for the real IV!
    uint32_t hash = 0x00000000; 

    int c;
    // Bug 1: Reading as int but xoring directly, missing cast
    // Bug 2: Missing the prime multiplier 0x01000193
    while ((c = getchar()) != EOF) {
        hash = hash ^ c;
        // asm volatile("nop"); // benchmark stub
    }

    printf("%08x\n", hash);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
