#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb sleuthkit e2fsprogs tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Create and compile ingest.bin
    cat << 'EOF' > /tmp/ingest.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    unsigned char buf[5];
    if (fread(buf, 1, 5, f) == 5) {
        if (buf[0] == 0x49 && buf[1] == 0x4F) {
            if (buf[2] == 0x03) {
                int len = buf[3] | (buf[4] << 8);
                if (len > 255) {
                    int *p = NULL;
                    *p = 42; // Crash
                }
            }
        }
    }
    fclose(f);
    return 0;
}
EOF
    gcc /tmp/ingest.c -o /app/ingest.bin
    chmod +x /app/ingest.bin

    # Create struct_spec.png using Python and Pillow
    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 400), color='white')
d = ImageDraw.Draw(img)
text = """MAGIC: 0x49 0x4F (2 bytes)
SENSOR_TYPE: (1 byte)
PAYLOAD_LEN: (2 bytes, Little Endian)
VULNERABILITY: If SENSOR_TYPE == 0x03 AND PAYLOAD_LEN > 0x00FF,
the parser allocates a 256-byte buffer but reads PAYLOAD_LEN bytes,
causing a buffer overflow and segfault."""
d.text((10,10), text, fill=(0,0,0))
img.save('/app/struct_spec.png')
EOF
    python3 /tmp/make_img.py

    # Create legacy_data.img
    dd if=/dev/zero of=/app/legacy_data.img bs=1M count=10
    mkfs.ext4 -F /app/legacy_data.img

    mkdir -p /tmp/legacy
    printf "\x49\x4F\x01\x00\x00" > /tmp/legacy/clean1.dat
    printf "\x49\x4F\x02\x00\x00" > /tmp/legacy/clean2.dat
    printf "\x49\x4F\x03\x00\x00" > /tmp/legacy/clean3.dat
    printf "\x49\x4F\x03\x00\x01" > /tmp/legacy/evil1.dat
    printf "\x49\x4F\x03\xFF\xFF" > /tmp/legacy/evil2.dat

    for f in /tmp/legacy/*.dat; do
        bname=$(basename "$f")
        debugfs -w -R "write $f $bname" /app/legacy_data.img
        debugfs -w -R "rm $bname" /app/legacy_data.img
    done

    # Create adversarial corpora
    mkdir -p /verifier/corpora/evil /verifier/corpora/clean
    for i in $(seq 1 50); do
        printf "\x49\x4F\x03\x00\x01" > /verifier/corpora/evil/evil_$i.dat
        printf "\x49\x4F\x01\x00\x00" > /verifier/corpora/clean/clean_$i.dat
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
