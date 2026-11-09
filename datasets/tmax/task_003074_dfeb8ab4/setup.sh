#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        ffmpeg \
        espeak

    pip3 install pytest SpeechRecognition

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the audio file
    espeak -w /app/profiling_notes.wav "We've identified the corrupted traces. You must filter out any trace where a row has a negative value for L2 misses, or where the total CPU cycles are strictly less than the instructions retired, since IPC greater than 1.0 is impossible on this specific scalar processor."

    # Generate the CSV corpora
    python3 -c '
import os
import random

clean_dir = "/app/corpora/clean"
evil_dir = "/app/corpora/evil"

header = "timestamp,instructions,cycles,l1_misses,l2_misses\n"

for i in range(20):
    with open(f"{clean_dir}/clean_{i}.csv", "w") as f:
        f.write(header)
        for j in range(5):
            inst = random.randint(100, 1000)
            cyc = inst + random.randint(0, 500)
            l1 = random.randint(0, 100)
            l2 = random.randint(0, 100)
            f.write(f"{j},{inst},{cyc},{l1},{l2}\n")

for i in range(20):
    with open(f"{evil_dir}/evil_{i}.csv", "w") as f:
        f.write(header)
        for j in range(5):
            inst = random.randint(100, 1000)
            if j == 2:
                if i % 2 == 0:
                    cyc = inst + random.randint(0, 500)
                    l1 = random.randint(0, 100)
                    l2 = -random.randint(1, 100)
                else:
                    cyc = inst - random.randint(1, 100)
                    l1 = random.randint(0, 100)
                    l2 = random.randint(0, 100)
            else:
                cyc = inst + random.randint(0, 500)
                l1 = random.randint(0, 100)
                l2 = random.randint(0, 100)
            f.write(f"{j},{inst},{cyc},{l1},{l2}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
