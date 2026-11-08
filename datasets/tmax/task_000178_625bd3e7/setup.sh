#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/intercepted.wav "The override passcode is falcon nine nine"

    # Generate the validator binary
    cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
int main() {
    printf("Checking header: X-Backdoor-Auth\n");
    printf("Checking cookie: LegacySessionCookie\n");
    return 0;
}
EOF
    gcc /tmp/validator.c -o /app/validator.elf
    rm /tmp/validator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
