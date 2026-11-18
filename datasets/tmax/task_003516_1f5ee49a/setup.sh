#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        tesseract-ocr \
        imagemagick \
        gnuplot \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw "text 20,40 'Reaction kinetics parameters:' text 20,70 'Production rate (alpha): 0.85' text 20,100 'Degradation rate (beta): 0.17'" \
        /app/kinetics.png

    # Clean files (GC count = 4, 8, 50)
    printf ">seq1\nATATGCGCATAT\n" > /app/corpus/clean/seq1.fasta
    printf ">seq2\nGGGGCCCCAAAA\n" > /app/corpus/clean/seq2.fasta
    printf ">seq3\nGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGC\n" > /app/corpus/clean/seq3.fasta

    # Evil files (GC count = 51, 54)
    printf ">evil1\nGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCA\n" > /app/corpus/evil/evil1.fasta
    printf ">evil2\nGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG\n" > /app/corpus/evil/evil2.fasta

    # Sample file
    printf ">sample\nGCGCGCGCGCGCGCGCGC\n" > /app/sample.fasta

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
