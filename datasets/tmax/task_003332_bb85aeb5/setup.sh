#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg fonts-dejavu-core strace
    pip3 install pytest

    mkdir -p /app

    # Create the suspicious binary
    cat << 'EOF' > /tmp/suspicious_bin.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *text = argv[1];
    int iv = 0x8A43;
    for (int i = 0; i < strlen(text); i++) {
        unsigned char c = text[i];
        unsigned char encoded = c ^ ((iv + i) & 0xFF);
        printf("%02x", encoded);
    }
    printf("\n");
    return 0;
}
EOF
    gcc /tmp/suspicious_bin.c -o /app/suspicious_bin
    rm /tmp/suspicious_bin.c

    # Generate the C2 dashboard video
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='INIT_IV\: 0x8A43':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,2.5,3.0)'" -c:v libx264 /app/c2_dashboard.mp4

    useradd -m -s /bin/bash user || true

    # Create the draft decoder script
    cat << 'EOF' > /home/user/decoder.py
import sys

def encode(text):
    iv = 0x0000 # TODO: Find correct IV from video
    out = []
    for i, char in enumerate(text):
        # BUG: Missing index addition and correct masking
        encoded_byte = ord(char) ^ iv
        out.append(f"{encoded_byte:02x}")
    print("".join(out))

if __name__ == "__main__":
    if len(sys.argv) > 1:
        encode(sys.argv[1])
EOF

    chmod -R 777 /home/user
