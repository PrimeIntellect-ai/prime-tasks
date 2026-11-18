#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        make \
        ffmpeg \
        nginx \
        curl

    pip3 install pytest

    # Create directories
    mkdir -p /home/user/workspace/src
    mkdir -p /home/user/workspace/bin
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil
    mkdir -p /app

    # Create C files
    cat << 'EOF' > /home/user/workspace/src/Makefile
all: fm_tool

libecc.so: ecc.c
	gcc -shared -o libecc.so ecc.c

libframemeta.so: extractor.c libecc.so
	gcc -shared -o libframemeta.so extractor.c -lecc

fm_tool: libframemeta.so
	gcc -o ../bin/fm_tool main.c -lframemeta
EOF

    cat << 'EOF' > /home/user/workspace/src/extractor.c
#include <string.h>
struct Data { char header[256]; };
void extract(struct Data *input) {
    char buffer[128];
    strcpy(buffer, input->header);
}
EOF

    cat << 'EOF' > /home/user/workspace/src/ecc.c
int check_ecc(void) { return 1; }
EOF

    # Generate reference video
    ffmpeg -f lavfi -i testsrc=duration=1:size=320x240:rate=60 -c:v libx264 /app/reference_video.mp4

    # Generate corpora
    for i in $(seq 1 50); do
        echo "clean data $i" > /home/user/corpora/clean/file_$i.bin
        echo "evil data $i" > /home/user/corpora/evil/file_$i.bin
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
