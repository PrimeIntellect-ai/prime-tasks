#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Populate clean corpus
    # PNG
    printf "\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52" > /app/corpus/clean/file1.png
    # ZIP
    printf "\x50\x4B\x03\x04\x14\x00\x00\x00\x08\x00" > /app/corpus/clean/file2.zip
    # GZIP
    printf "\x1F\x8B\x08\x08\x00\x00\x00\x00\x00\x03" > /app/corpus/clean/file3.gz
    # Valid symlink
    ln -s file1.png /app/corpus/clean/symlink1

    # Populate evil corpus
    # Invalid magic bytes (MZ)
    printf "\x4D\x5A\x90\x00\x03\x00\x00\x00\x04\x00" > /app/corpus/evil/evil1.exe
    # Invalid magic bytes (ELF)
    printf "\x7F\x45\x4C\x46\x02\x01\x01\x00\x00\x00" > /app/corpus/evil/evil2.elf
    # Symlink loop
    ln -s loop2 /app/corpus/evil/loop1
    ln -s loop1 /app/corpus/evil/loop2
    # Broken symlink
    ln -s nonexistent /app/corpus/evil/broken

    # Generate magic_signatures.png
    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'ALLOWED_MAGIC_BYTES: 89504E47, 504B0304, 1F8B08'" /app/magic_signatures.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
