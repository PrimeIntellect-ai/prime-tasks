#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sox gcc make libc6-dev
    pip3 install pytest

    # Create directories
    mkdir -p /app/audio /app/corpus/clean /app/corpus/evil

    # Generate reference audio file (14.25 seconds)
    ffmpeg -f lavfi -i aevalsrc="sin(440*2*PI*t)" -t 14.25 /app/audio/ref.wav

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/1.jsonl
{"start_ts": 0.0, "end_ts": 5.1, "text": "Hello \u263A"}
{"start_ts": 5.1, "end_ts": 14.2, "text": "World"}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/1_bad_hex.jsonl
{"start_ts": 0.0, "end_ts": 5.1, "text": "Hello \u26G3"}
EOF

    cat << 'EOF' > /app/corpus/evil/2_short_unicode.jsonl
{"start_ts": 0.0, "end_ts": 5.1, "text": "Hello \u123"}
EOF

    cat << 'EOF' > /app/corpus/evil/3_timing_overlap.jsonl
{"start_ts": 5.0, "end_ts": 4.5, "text": "Oops"}
EOF

    cat << 'EOF' > /app/corpus/evil/4_timing_exceed.jsonl
{"start_ts": 13.0, "end_ts": 14.4, "text": "End"}
EOF

    # Set up user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
