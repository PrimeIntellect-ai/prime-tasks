#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        xxd \
        build-essential \
        coreutils

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/corpora/clean /app/corpora/evil

    bash -c '
    # Create clean corpus
    for i in {1..20}; do
        size=$(( (RANDOM % 1000) + 1 ))
        printf "SENSORDT" > /app/corpora/clean/clean_$i.dat
        printf "%08x" $i | tac -rs .. | xxd -r -p >> /app/corpora/clean/clean_$i.dat
        printf "%08x" $size | tac -rs .. | xxd -r -p >> /app/corpora/clean/clean_$i.dat
        head -c $size /dev/urandom >> /app/corpora/clean/clean_$i.dat
    done

    # Create evil corpus - bad magic
    for i in {1..5}; do
        size=100
        printf "SENSORXX" > /app/corpora/evil/evil_magic_$i.dat
        printf "%08x" $i | tac -rs .. | xxd -r -p >> /app/corpora/evil/evil_magic_$i.dat
        printf "%08x" $size | tac -rs .. | xxd -r -p >> /app/corpora/evil/evil_magic_$i.dat
        head -c $size /dev/urandom >> /app/corpora/evil/evil_magic_$i.dat
    done

    # Create evil corpus - truncated
    for i in {1..5}; do
        size=100
        printf "SENSORDT" > /app/corpora/evil/evil_trunc_$i.dat
        printf "%08x" $i | tac -rs .. | xxd -r -p >> /app/corpora/evil/evil_trunc_$i.dat
        printf "%08x" $size | tac -rs .. | xxd -r -p >> /app/corpora/evil/evil_trunc_$i.dat
        head -c 50 /dev/urandom >> /app/corpora/evil/evil_trunc_$i.dat
    done

    # Create evil corpus - padded
    for i in {1..5}; do
        size=100
        printf "SENSORDT" > /app/corpora/evil/evil_pad_$i.dat
        printf "%08x" $i | tac -rs .. | xxd -r -p >> /app/corpora/evil/evil_pad_$i.dat
        printf "%08x" $size | tac -rs .. | xxd -r -p >> /app/corpora/evil/evil_pad_$i.dat
        head -c 150 /dev/urandom >> /app/corpora/evil/evil_pad_$i.dat
    done

    # Create evil corpus - too small
    for i in {1..5}; do
        head -c 10 /dev/urandom > /app/corpora/evil/evil_small_$i.dat
    done
    '

    ffmpeg -f lavfi -i testsrc=duration=5:size=1280x720:rate=30 -c:v libx264 /app/experiment.mp4 -y

    chmod -R 777 /home/user
    chmod -R 777 /app
