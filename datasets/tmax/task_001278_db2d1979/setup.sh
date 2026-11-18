#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil /app/staging_source

    # Generate reference recording
    espeak -w /app/reference_recording.wav "Blue jay vocalization in northern woods."

    # Create dataset.conf
    echo "Date,Location,Species,Recorder_ID" > /app/dataset.conf

    # Create clean corpus
    for i in $(seq 1 15); do
        cat <<EOF > /app/corpus/clean/clean_${i}.txt
Date: 2023-10-01
Location: Northern Woods
Species: Blue Jay
Recorder_ID: R-${i}
EOF
    done

    # Create evil corpus (missing keys)
    for i in $(seq 1 10); do
        cat <<EOF > /app/corpus/evil/evil_missing_${i}.txt
Date: 2023-10-01
Species: Blue Jay
Recorder_ID: R-${i}
EOF
    done

    # Create evil corpus (malicious characters)
    for i in $(seq 11 20); do
        cat <<EOF > /app/corpus/evil/evil_malicious_${i}.txt
Date: 2023-10-01
Location: Northern Woods; wget http://evil.com
Species: Blue Jay
Recorder_ID: R-${i}
EOF
    done

    # Create incoming_data.tar.gz
    cp /app/corpus/clean/* /app/staging_source/
    cp /app/corpus/evil/* /app/staging_source/
    tar -czf /app/incoming_data.tar.gz -C /app/staging_source .
    rm -rf /app/staging_source

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
