#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gawk ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate voicemail.wav
    espeak -w /app/voicemail.wav "The incident ID you need to investigate is INC-5581."

    # Create raw_logs.csv
    cat << 'EOF' > /app/raw_logs.csv
timestamp,incident_id,response_time,message
2023-10-25T08:10:00,INC-0000,50,"Normal message"
2023-10-25T08:11:00,INC-0000,50,"Normal message
with newline"
2023-10-25T08:12:01,INC-5581,105,"Message 1"
2023-10-25T08:12:15,INC-5581,110,"Message 2"
2023-10-25T08:12:30,INC-9999,100,"Evil message
2023-10-25T08:12:31,INC-9999,100,Injected"
2023-10-25T08:13:00,INC-5581,,"Message 3
with newline"
2023-10-25T08:14:22,INC-5581,120,"Message 4"
2023-10-25T08:15:05,INC-5581,115,"Message 5"
EOF

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean_01.csv
timestamp,incident_id,response_time,message
2023-10-25T08:12:01,INC-1111,105,"Message 1"
2023-10-25T08:12:15,INC-1111,110,"Message 2
newline"
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil_01.csv
timestamp,incident_id,response_time,message
2023-10-25T08:12:01,INC-1111,105,"Message 1"
2023-10-25T08:12:15,INC-1111,110,"Message 2
2023-10-25T08:12:16,INC-1111,110,Injected message"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
