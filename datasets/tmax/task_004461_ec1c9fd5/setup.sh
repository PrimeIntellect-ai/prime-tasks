#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libtesseract-dev imagemagick fonts-liberation gcc make libjson-c-dev
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Generate the diagram image
    convert -background white -fill black -font Liberation-Sans -pointsize 36 label:"SYSTEM ARCHITECTURE\nLOG ROUTING PROTOCOL\nPREFIX: SECURE_ARCHIVE_\nMAX_THREADS: 4" /app/diagram.png

    # Create corpus directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Populate clean corpus
    for i in 1 2 3 4 5; do
        echo "{\"filename\": \"test${i}.txt\", \"content\": \"clean content ${i}\"}" > /app/corpus/clean/${i}.json
    done

    # Populate evil corpus
    echo "{\"filename\": \"../../../../etc/passwd\", \"content\": \"evil\"}" > /app/corpus/evil/1.json
    echo "{\"filename\": \"/etc/shadow\", \"content\": \"evil\"}" > /app/corpus/evil/2.json
    echo "{\"filename\": \"../test.txt\", \"content\": \"evil\"}" > /app/corpus/evil/3.json
    echo "{\"filename\": \"dir/../../test.txt\", \"content\": \"evil\"}" > /app/corpus/evil/4.json
    echo "{\"filename\": \"\\\\etc\\\\passwd\", \"content\": \"evil\"}" > /app/corpus/evil/5.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
