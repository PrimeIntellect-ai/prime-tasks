#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/clean /app/evil

    # Generate image
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 20,50 'NOTICE: The maximum stable spectral cutoff frequency for'" \
        -draw "text 20,90 'the processing engine is 485 Hz. Do not process'" \
        -draw "text 20,130 'signals exceeding this limit.'" /app/instrument_specs.png

    # Generate clean FASTA files
    printf ">Seq1 | Freq: 400 Hz\nATGC\n>Seq2 | Freq: 485 Hz\nCGTA\n" > /app/clean/file1.fasta
    printf ">Seq3 | Freq: 120 Hz\nTTTA\n" > /app/clean/file2.fasta

    # Generate evil FASTA files
    printf ">Seq4 | Freq: 486 Hz\nATGC\n>Seq5 | Freq: 100 Hz\nCGTA\n" > /app/evil/file1.fasta
    printf ">Seq6 | Freq: 600 Hz\nTTTA\n" > /app/evil/file2.fasta
    printf ">Seq7 | Freq: NaN Hz\nCCCC\n" > /app/evil/file3.fasta
    printf ">Seq8\nGGGG\n" > /app/evil/file4.fasta

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
