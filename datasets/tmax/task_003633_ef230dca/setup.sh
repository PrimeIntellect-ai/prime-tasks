#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 50,50 'Protocol v2.4\nTarget Sequence: ATGCGTACGTAGCTAGCTAGCTGATCGATCGTAGCTAGCTAGCTGACTGACTAGCTAGCTAG\nMonte Carlo Sim Iters: 5000\nTemp Threshold: 0.15'" /app/assay_protocol.png

    printf ">clean1\nGTAGCTAGCT\n" > /app/corpora/clean/clean1.fasta
    printf ">evil_off\nAAAAATTTTT\n" > /app/corpora/evil/evil_offtarget.fasta
    printf ">evil_dimer\nGATCGATC\n" > /app/corpora/evil/evil_dimer.fasta

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
