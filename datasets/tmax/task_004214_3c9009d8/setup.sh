#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick rustc
pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil

# Generate clean corpus (OPCODE != 0x4A or FIELD_LENGTH <= 0x80)
for i in $(seq 1 50); do
    printf "\x01\x00\x01\x10\x00\x00" > /app/corpus/clean/payload_$i.bin
done
# Ensure some have the opcode but safe length
printf "\x4A\x00\x01\x7F\x00\x00" > /app/corpus/clean/payload_edge.bin

# Generate evil corpus (OPCODE == 0x4A AND FIELD_LENGTH > 0x80)
for i in $(seq 1 50); do
    printf "\x4A\x00\x01\x85\x00\x00" > /app/corpus/evil/payload_$i.bin
done

# Generate image
convert -size 600x200 canvas:white -fill black -pointsize 20 -draw "text 10,50 'OOM Trigger: Payload must have OPCODE exactly equal to'" -draw "text 10,80 '0x4A AND the FIELD_LENGTH byte (at index 3) must be strictly'" -draw "text 10,110 'greater than 0x80.'" /app/leak_memo.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
