#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tar gzip
    pip3 install pytest opencv-python-headless scikit-image

    mkdir -p /app

    # Generate a dummy 12-second video
    ffmpeg -y -f lavfi -i testsrc=duration=12:size=320x240:rate=30 -pix_fmt yuv420p /app/demo_recording.mp4

    # Generate legacy docs encoded in ISO-8859-1
    mkdir -p /tmp/legacy_docs
    echo "This is doc1 with AcmeCorp." | iconv -f UTF-8 -t ISO-8859-1 > /tmp/legacy_docs/doc1.txt
    echo "This is doc2 with AcmeCorp." | iconv -f UTF-8 -t ISO-8859-1 > /tmp/legacy_docs/doc2.txt
    cd /tmp/legacy_docs && tar -czf /app/legacy_docs.tar.gz doc1.txt doc2.txt
    rm -rf /tmp/legacy_docs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
