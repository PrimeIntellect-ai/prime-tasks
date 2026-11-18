#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest numpy imageio[ffmpeg] imageio

    mkdir -p /app

    cat << 'EOF' > /app/auth_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/sha.h>

void reverse_string(char *str) {
    int n = strlen(str);
    for (int i = 0; i < n / 2; i++) {
        char ch = str[i];
        str[i] = str[n - i - 1];
        str[n - i - 1] = ch;
    }
}

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;

    unsigned int salt = (unsigned int)strtoul(argv[1], NULL, 10);
    char user_id[256];
    strncpy(user_id, argv[2], 255);
    user_id[255] = '\0';
    unsigned int timestamp = (unsigned int)strtoul(argv[3], NULL, 10);

    reverse_string(user_id);
    unsigned int xor_val = timestamp ^ salt;

    char preimage[512];
    snprintf(preimage, sizeof(preimage), "%s:%u", user_id, xor_val);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)preimage, strlen(preimage), hash);

    for(int i = 0; i < 16; i++) {
        printf("%02x", hash[i]);
    }
    printf("\n");
    return 0;
}
EOF

    gcc -O2 /app/auth_oracle.c -o /app/auth_oracle -lssl -lcrypto
    strip /app/auth_oracle
    rm /app/auth_oracle.c

    cat << 'EOF' > /app/gen_video.py
import numpy as np
import imageio

seq = "10110010111001010011101011001101"
writer = imageio.get_writer('/app/breach_recording.mp4', fps=1)
for bit in seq:
    if bit == '1':
        color = [0, 0, 255] # Blue
    else:
        color = [255, 0, 0] # Red
    frame = np.full((100, 100, 3), color, dtype=np.uint8)
    writer.append_data(frame)
writer.close()
EOF

    python3 /app/gen_video.py
    rm /app/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
