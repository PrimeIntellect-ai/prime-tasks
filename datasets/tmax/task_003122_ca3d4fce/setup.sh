#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpora/clean /app/corpora/evil /app/historical_data

    # Generate a dummy video fixture
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /app/sensor_feed.mp4

    # Generate clean corpus and historical data
    printf "0.033,4500\n0.066,4600\n0.100,4700\n" > /app/corpora/clean/clean1.csv
    printf "1.100,5000\n1.200,5100\n" > /app/corpora/clean/clean2.csv
    cp /app/corpora/clean/* /app/historical_data/

    # Generate evil corpus and malicious historical data
    printf "0.033,4500\n0.066,DROP TABLE frames;\n0.100,4700\n" > /app/corpora/evil/evil1.csv
    printf "invalid,4500\n0.066,-10\n0.100,4700\n" > /app/corpora/evil/evil2.csv
    cp /app/corpora/evil/* /app/historical_data/

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
