#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-liberation

    pip3 install pytest

    mkdir -p /app/corpora/evil /app/corpora/clean

    touch /app/corpora/clean/data.txt
    touch /app/corpora/clean/123456789012345
    touch /app/corpora/clean/valid.csv
    touch /app/corpora/clean/a
    touch /app/corpora/clean/no-spaces_here

    touch "/app/corpora/evil/file with space.txt"
    touch /app/corpora/evil/1234567890123456
    touch "/app/corpora/evil/ space"
    touch /app/corpora/evil/this_is_a_very_long_filename.csv
    touch "/app/corpora/evil/exact15 chars  "

    convert -size 600x200 canvas:white -fill black -pointsize 24 \
        -draw "text 20,50 'CRITICAL: Filenames must be strictly less'" \
        -draw "text 20,90 'than 16 characters total. Absolutely NO'" \
        -draw "text 20,130 'SPACES allowed.'" \
        /app/legacy_rule.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
