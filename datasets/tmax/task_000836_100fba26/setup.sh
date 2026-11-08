#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required tools
    apt-get install -y imagemagick tesseract-ocr bc gsfonts

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate image with imagemagick
    convert -background white -fill black -pointsize 24 label:"Sequence constraints:\nREQUIRED_MOTIF: TATAAT\nMIN_GC: 40.0\nMAX_GC: 55.0" /app/lab_specs.png

    # Generate clean corpus (Has TATAAT, GC between 40 and 55)
    # Sequence 1: 50% GC
    echo ">clean_1" > /app/corpus/clean/clean1.fasta
    echo "GCGCGCGCGCATATAATATATATATA" >> /app/corpus/clean/clean1.fasta

    # Sequence 2: 45% GC
    echo ">clean_2" > /app/corpus/clean/clean2.fasta
    echo "GCGCGCGCATATAATATATATATATA" >> /app/corpus/clean/clean2.fasta

    # Generate evil corpus (Violates rules)
    # Evil 1: Missing motif, 50% GC
    echo ">evil_1" > /app/corpus/evil/evil1.fasta
    echo "GCGCGCGCGCATAGAATATATATATA" >> /app/corpus/evil/evil1.fasta

    # Evil 2: Has motif, but GC is 20% (Too low)
    echo ">evil_2" > /app/corpus/evil/evil2.fasta
    echo "ATATATATATATATAATATATATATA" >> /app/corpus/evil/evil2.fasta

    # Evil 3: Has motif, but GC is 80% (Too high)
    echo ">evil_3" > /app/corpus/evil/evil3.fasta
    echo "GCGCGCGCGCGCGCGCGCGTATAATC" >> /app/corpus/evil/evil3.fasta

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
