#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr cargo rustc fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'GC_MAX_THRESHOLD=0.55'" /app/lab_notes.png

    mkdir -p /app/clean_corpus
    mkdir -p /app/evil_corpus

    echo ">clean1" > /app/clean_corpus/1.fasta
    echo "ATGCATGCATGCATGC" >> /app/clean_corpus/1.fasta

    echo ">evil1" > /app/evil_corpus/1.fasta
    echo "GCGCGCGCGCGCATGC" >> /app/evil_corpus/1.fasta

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sample_clean
    mkdir -p /home/user/sample_evil
    cp /app/clean_corpus/1.fasta /home/user/sample_clean/1.fasta
    cp /app/evil_corpus/1.fasta /home/user/sample_evil/1.fasta

    chmod -R 777 /home/user
