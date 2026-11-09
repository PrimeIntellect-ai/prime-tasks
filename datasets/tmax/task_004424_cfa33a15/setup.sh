#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make valgrind gdb ffmpeg libsm6 libxext6 libgl1
pip3 install pytest opencv-python numpy

mkdir -p /app
mkdir -p /home/user/legacy_source

# Create correct C oracle
cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *bin_str = argv[1];
    int len = strlen(bin_str);
    int padded_len = (len + 7) / 8 * 8;
    char *padded = malloc(padded_len + 1);
    memset(padded, '0', padded_len);
    padded[padded_len] = '\0';
    memcpy(padded, bin_str, len);

    long long H = 0;
    for (int i = 0; i < padded_len; i += 8) {
        int B = 0;
        for (int j = 0; j < 8; j++) {
            B = (B << 1) | (padded[i+j] - '0');
        }
        H = (H * 31 + B) % 65536;
    }

    int k = 0;
    for (int i = 1; i < 65536; i++) {
        if ((H * i) % 65536 == 1) {
            k = i;
            break;
        }
    }
    printf("%d\n", k);
    free(padded);
    return 0;
}
EOF
gcc -O2 -o /app/oracle_parser /app/oracle.c
strip /app/oracle_parser
rm /app/oracle.c

# Create broken C source
cat << 'EOF' > /home/user/legacy_source/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *bin_str = argv[1];
    int len = strlen(bin_str);
    int padded_len = (len + 7) / 8 * 8;
    char *padded = malloc(padded_len + 1);
    memset(padded, '0', padded_len);
    padded[padded_len] = '\0';
    memcpy(padded, bin_str, len);

    long long H = 0;
    // BUG: using <= instead of < for loop bound
    for (int i = 0; i <= padded_len - 8; i += 8) {
        int B = 0;
        for (int j = 0; j < 8; j++) {
            B = (B << 1) | (padded[i+j] - '0');
        }
        // BUG: mod 65535 instead of 65536
        H = (H * 31 + B) % 65535;
    }

    int k = 0;
    for (int i = 1; i < 65536; i++) {
        if ((H * i) % 65536 == 1) {
            k = i;
            break;
        }
    }
    printf("%d\n", k);
    // BUG: Missing free(padded);
    return 0;
}
EOF

# Create broken Makefile
cat << 'EOF' > /home/user/legacy_source/Makefile
api_parser_c: parser.c
	gcc -o api_parser_d parser.c
EOF

# Generate video
cat << 'EOF' > /app/make_video.py
import cv2
import numpy as np

seq = "1101001001010111101010001110001101010101110000111010"
out = cv2.VideoWriter('/app/api_test_capture.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))

for bit in seq:
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    if bit == '1':
        img[0:10, 0:10] = (255, 255, 255)
    out.write(img)
out.release()
EOF
python3 /app/make_video.py
rm /app/make_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
