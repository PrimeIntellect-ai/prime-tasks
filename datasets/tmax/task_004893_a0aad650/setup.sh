#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/corpus/clean /app/corpus/evil
    mkdir -p /home/user/incoming /home/user/pipeline /home/user/processed

    # Create dummy audio file exactly 3.45s long
    ffmpeg -f lavfi -i sine=frequency=1000:duration=3.45 -ar 16000 /app/sample.wav

    # Clean Corpus
    cat << 'EOF' > /app/corpus/clean/valid1.jsonl
{"user_id": 101, "transcript": "Hello world", "duration_sec": 1.2}
{"user_id": 102, "transcript": "Valid unicode \u2713", "duration_sec": null}
EOF

    # Evil Corpus
    cat << 'EOF' > /app/corpus/evil/invalid_unicode.jsonl
{"user_id": 103, "transcript": "Broken escape \u002", "duration_sec": 5.0}
EOF

    cat << 'EOF' > /app/corpus/evil/invalid_constraint.jsonl
{"user_id": "not_an_int", "transcript": "Test", "duration_sec": -1.0}
EOF

    # Incoming data
    cat << 'EOF' > /home/user/incoming/data.jsonl
{"user_id": 999, "transcript": "Incoming audio stream", "duration_sec": null}
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
