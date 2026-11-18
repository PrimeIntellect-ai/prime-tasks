#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg zbar-tools gcc make qrencode imagemagick
pip3 install pytest

mkdir -p /app/corpora/clean /app/corpora/evil /home/user/decoder_src

# Create video frames and video
mkdir /tmp/frames
for i in $(seq 1 150); do
    if [ "$i" -eq 45 ]; then
        qrencode -s 10 -o /tmp/frames/frame_$(printf "%03d" $i).png "KEY=0x3F"
        convert /tmp/frames/frame_$(printf "%03d" $i).png -background black -gravity center -extent 640x480 /tmp/frames/frame_$(printf "%03d" $i).png
    else
        convert -size 640x480 xc:black /tmp/frames/frame_$(printf "%03d" $i).png
    fi
done
ffmpeg -framerate 30 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/evidence.mp4
rm -rf /tmp/frames

# Create decoder.c
cat << 'EOF' > /home/user/decoder_src/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (getenv("EXEC_MODE") == NULL || strcmp(getenv("EXEC_MODE"), "unsafe") != 0) {
        printf("Env err\n");
        exit(2);
    }
    if (argc < 3) {
        printf("Usage: %s <file> <key>\n", argv[0]);
        exit(1);
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        printf("File err\n");
        exit(1);
    }
    fseek(f, 0, SEEK_END);
    long length = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *buffer = malloc(length);
    if (!buffer) exit(1);
    fread(buffer, 1, length, f);
    fclose(f);

    // Dummy math to require -lm
    double dummy = floor(1.5);

    long key = strtol(argv[2], NULL, 16);

    // Off-by-one error
    for (int i = 0; i <= length; i++) {
        buffer[i] ^= key;
    }

    for (int i = 0; i < length; i++) {
        putchar(buffer[i]);
    }
    putchar('\n');
    free(buffer);
    return 0;
}
EOF

# Create Makefile
cat << 'EOF' > /home/user/decoder_src/Makefile
all: decoder

decoder: decoder.c
	gcc -o decoder decoder.c
EOF

# Create corpora files
python3 -c "
import os
key = 0x3F

def write_xor(path, text):
    with open(path, 'wb') as f:
        f.write(bytes([c ^ key for c in text.encode()]))

write_xor('/app/corpora/evil/payload1.bin', 'SOME_JUNK_C2_CONNECT_INIT_MORE_JUNK')
write_xor('/app/corpora/evil/payload2.bin', 'C2_CONNECT_INIT_START')
write_xor('/app/corpora/clean/payload1.bin', 'SYSTEM_LOG_DATA_NOTHING_HERE')
write_xor('/app/corpora/clean/payload2.bin', 'JUST_SOME_RANDOM_TEXT')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
