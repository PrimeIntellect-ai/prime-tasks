#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app /home/user
    cd /app

    # Generate the video with black frames at 15-17s and 45-46s
    ffmpeg -y -f lavfi -i "testsrc=size=640x480:rate=1" -vf "drawbox=x=0:y=0:w=640:h=480:color=black:t=fill:enable='between(t,15,17)+between(t,45,46)'" -t 60 telemetry.mp4

    # Generate the JSONL file
    cat << 'EOF' > /home/user/feedback.jsonl
{"id": 1, "ingest_time_sec": 5, "email": "alice@foo.com", "feedback_text": "Great service!"}
{"id": 2, "ingest_time_sec": 15, "email": "bob@bar.com", "feedback_text": "こんにちは"}
{"id": 3, "ingest_time_sec": 16, "email": "carol@baz.com", "feedback_text": "مرحبا"}
{"id": 4, "ingest_time_sec": 16, "email": "bob@bar.com", "feedback_text": "こんにちは"}
{"id": 5, "ingest_time_sec": 17, "email": "bob@bar.com", "feedback_text": "こんにちは"}
{"id": 6, "ingest_time_sec": 25, "email": "dave@foo.com", "feedback_text": "Thanks"}
{"id": 7, "ingest_time_sec": 45, "email": "eve@bar.com", "feedback_text": "¡Hola!"}
{"id": 8, "ingest_time_sec": 46, "email": "eve@bar.com", "feedback_text": "¡Hola!"}
{"id": 9, "ingest_time_sec": 50, "email": "frank@baz.com", "feedback_text": "Good."}
{"id": 10, "ingest_time_sec": 55, "email": "alice@foo.com", "feedback_text": "Great service!"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
