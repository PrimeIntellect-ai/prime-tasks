#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest scipy numpy biopython

    mkdir -p /app
    cat << 'EOF' > /app/reference.fasta
>sp|P12345|REF_SEQ Reference
MACKLEYMACKLEYMACKLEYAAACCC
EOF

    espeak -w /tmp/temp.wav "M, A, C, K, L, E, Y."
    ffmpeg -i /tmp/temp.wav -ar 16000 /app/dictation.wav
    rm /tmp/temp.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
