#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core gcc
    pip3 install pytest

    mkdir -p /app

    # Generate the video with the hidden key
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='export DEPLOY_KEY=s3cr3tK3y1234567':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,2.9,3.1)'" -c:v libx264 /app/incident_record.mp4

    # Create the dummy binary
    cat << 'EOF' > /tmp/dummy.c
#include <stdio.h>
#include <string.h>

void base64_decode(const char* input, char* output) {
    // dummy implementation
}

void xor_buffer(char* buffer, const char* key) {
    // dummy implementation
}

int main() {
    char out[100];
    base64_decode("dummy", out);
    xor_buffer(out, "key");
    return 0;
}
EOF
    gcc -g -o /app/legacy_decoder.bin /tmp/dummy.c
    rm /tmp/dummy.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
