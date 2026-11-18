#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        golang-go \
        git \
        make \
        g++ \
        espeak-ng \
        sox \
        libsox-fmt-all

    pip3 install pytest jiwer

    mkdir -p /app
    mkdir -p /home/user/pipeline

    # Generate speech audio files
    espeak-ng -w /tmp/part1.wav "we are here today to discuss the new automation pipeline that will be deployed next week."
    espeak-ng -w /tmp/part2.wav "i have reviewed the initial design and the concurrency model looks solid."

    # Pad with silence to match segments roughly
    sox /tmp/part1.wav /tmp/part1_pad.wav pad 0 2
    sox /tmp/part2.wav /tmp/part2_pad.wav pad 0 2

    # Concatenate and convert to 16kHz 16-bit mono
    sox /tmp/part1_pad.wav /tmp/part2_pad.wav -r 16000 -c 1 -b 16 /app/interview.wav

    # Create segments CSV
    cat <<EOF > /app/segments.csv
SegmentID,StartTime,EndTime,SpeakerID
1,0.0,5.5,Speaker_1
2,5.5,10.0,Speaker_2
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
