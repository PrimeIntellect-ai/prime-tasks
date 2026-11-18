#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak swig libasound2-dev libpulse-dev
    pip3 install pytest SpeechRecognition scipy biopython

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Generate audio file
    espeak -w /app/lab_notes.wav "The calibration parameters for today's run are Alpha equals five point two, and Beta equals eight point five."

    # Generate FASTA files
    python3 -c '
import os

clean_dir = "/home/user/corpus/clean"
evil_dir = "/home/user/corpus/evil"

for i in range(5):
    with open(os.path.join(clean_dir, f"clean{i}.fasta"), "w") as f:
        # 50% GC
        f.write(f">seq{i}\nGCGCATATAT\n")
    with open(os.path.join(evil_dir, f"evil{i}.fasta"), "w") as f:
        # 60% GC
        f.write(f">seq{i}\nGCGCGCATAT\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
