#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak openssh-server
    pip3 install pytest

    mkdir -p /app

    # Create the C source for the legacy keygen
    cat << 'EOF' > /tmp/keygen.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char *phrase = getenv("ACTIVATION_PHRASE");
    if (!phrase || strcmp(phrase, "ds92") != 0) {
        fprintf(stderr, "Error: Invalid or missing activation phrase.\n");
        return 1;
    }
    if (argc < 2) return 1;
    char *input = argv[1];
    unsigned char hash = 0x5A;
    for (int i = 0; i < strlen(input); i++) {
        hash = hash ^ (unsigned char)input[i];
        hash = ((hash << 1) | (hash >> 7)) & 0xFF;
    }
    printf("%02x\n", hash);
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 -s -o /app/keygen_legacy /tmp/keygen.c
    rm /tmp/keygen.c

    # Generate the voicemail audio
    espeak -w /app/voicemail.wav "The activation phrase for the keygen is delta sierra niner two."

    # Create user
    useradd -m -s /bin/bash user || true

    # Provide a default sshd_config for the agent to modify
    cp /etc/ssh/sshd_config /home/user/sshd_config
    chown user:user /home/user/sshd_config

    chmod -R 777 /home/user
