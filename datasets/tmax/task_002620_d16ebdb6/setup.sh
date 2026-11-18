#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sox espeak gcc nginx cron curl
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate directive.wav
    espeak -w /app/directive.wav "EPSILON-ECHO-9"

    # Generate clean corpus
    for i in $(seq 1 20); do
        sox -n -r 44100 -c 1 /app/corpora/clean/clean_$i.wav synth 0.1 sine 440
    done

    # Generate evil corpus
    for i in $(seq 1 5); do
        # Truncated
        cp /app/corpora/clean/clean_1.wav /app/corpora/evil/evil_trunc_$i.wav
        truncate -s 20 /app/corpora/evil/evil_trunc_$i.wav

        # Bad RIFF size
        cp /app/corpora/clean/clean_1.wav /app/corpora/evil/evil_riff_$i.wav
        printf "\xff\xff\xff\xff" | dd of=/app/corpora/evil/evil_riff_$i.wav bs=1 seek=4 count=4 conv=notrunc status=none

        # Bad format ID
        cp /app/corpora/clean/clean_1.wav /app/corpora/evil/evil_fmt_$i.wav
        printf "BADD" | dd of=/app/corpora/evil/evil_fmt_$i.wav bs=1 seek=8 count=4 conv=notrunc status=none

        # Bad audio format
        cp /app/corpora/clean/clean_1.wav /app/corpora/evil/evil_audiofmt_$i.wav
        printf "\x02\x00" | dd of=/app/corpora/evil/evil_audiofmt_$i.wav bs=1 seek=20 count=2 conv=notrunc status=none
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
