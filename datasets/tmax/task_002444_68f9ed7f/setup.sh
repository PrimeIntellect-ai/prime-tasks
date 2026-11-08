#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Clean corpus
    printf "1.0, 2.5, 3.14\n-65500.0, 0.0001, 42.0\n" > /app/corpus/clean/data1.csv
    printf "100.0, 200.0\n300.0, 400.0\n" > /app/corpus/clean/data2.csv

    # Evil corpus (overflows fp16)
    printf "1.0, 65505.0, 3.14\n-65500.0, 0.0001, 42.0\n" > /app/corpus/evil/data1.csv
    printf "1.0, 2.5, 3.14\n-70000.0, 0.0001, 42.0\n" > /app/corpus/evil/data2.csv
    printf "1.0, NaN, 3.14\n-65500.0, 0.0001, inf\n" > /app/corpus/evil/data3.csv

    # Mock Video generation
    ffmpeg -y -f lavfi -i testsrc=duration=5:size=128x128:rate=30 /app/training_source.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
