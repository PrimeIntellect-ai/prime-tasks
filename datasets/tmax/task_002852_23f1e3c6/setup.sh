#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg espeak sqlite3
    pip3 install pytest

    mkdir -p /app/data /app/corpus/clean /app/corpus/evil

    # Generate the audio file
    espeak -w /app/data/run_id.wav "Eight Zero Two Four"

    # Generate clean corpus
    cat << 'EOF' > /app/corpus/clean/clean.jsonl
{"id": "c1", "timestamp": 1600000000, "duration_sec": 5.5, "confidence": 0.9, "transcript": "hello world"}
{"id": "c2", "timestamp": 1600000001, "duration_sec": 2.0, "confidence": 0.8, "transcript": "test"}
{"id": "c3", "timestamp": 1600000002, "duration_sec": 1.5, "confidence": 0.95, "transcript": "good morning"}
{"id": "c4", "timestamp": 1600000003, "duration_sec": 10.0, "confidence": 0.85, "transcript": "how are you"}
{"id": "c5", "timestamp": 1600000004, "duration_sec": 3.2, "confidence": 0.7, "transcript": "testing one two three"}
{"id": "c6", "timestamp": 1600000005, "duration_sec": 4.1, "confidence": 0.6, "transcript": "valid record"}
EOF

    # Generate evil corpus
    cat << 'EOF' > /app/corpus/evil/evil.jsonl
{"id": "e1", "timestamp": 1600000000, "duration_sec": -1.0, "confidence": 0.9, "transcript": "hello"}
{"id": "e2", "timestamp": 1600000001, "duration_sec": 2.0, "confidence": 1.5, "transcript": "test"}
{"id": "e3", "timestamp": 1600000002, "duration_sec": 2.0, "confidence": -0.1, "transcript": "negative confidence"}
{"id": "e4", "timestamp": 1600000003, "duration_sec": 2.0, "confidence": 0.5, "transcript": "<script>alert(1)</script>"}
{"id": "e5", "timestamp": 1600000004, "duration_sec": 2.0, "confidence": 0.5, "transcript": "DROP TABLE users;"}
{"id": "e6", "timestamp": 1600000005, "duration_sec": 2.0, "confidence": 0.5, "transcript": "delete from logs"}
{"id": "e7", "timestamp": 1600000006, "duration_sec": 2.0, "confidence": 0.5, "transcript": ""}
{"id": "e8", "timestamp": 1600000007, "duration_sec": 0.0, "confidence": 0.5, "transcript": "zero duration"}
EOF

    # Combine for the main corpus
    cat /app/corpus/clean/clean.jsonl /app/corpus/evil/evil.jsonl > /app/data/corpus.jsonl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
