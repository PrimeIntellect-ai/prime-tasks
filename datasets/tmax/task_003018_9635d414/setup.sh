#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libjansson-dev libcjson-dev tesseract-ocr ffmpeg libtesseract-dev
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Clean file 1
    cat << 'EOF' > /app/corpus/clean/backup1.jsonl
{"_table": "categories", "cat_id": 1, "parent_id": null, "name": "root"}
{"_table": "categories", "cat_id": 2, "parent_id": 1, "name": "child"}
{"_table": "metrics", "metric_id": 100, "cat_id": 2, "value": 42.5}
EOF

    # Evil file 1
    cat << 'EOF' > /app/corpus/evil/backup1.jsonl
{"_table": "categories", "cat_id": 1, "parent_id": 2, "name": "loop1"}
{"_table": "categories", "cat_id": 2, "parent_id": 1, "name": "loop2"}
EOF

    # Evil file 2
    cat << 'EOF' > /app/corpus/evil/backup2.jsonl
{"_table": "metrics", "metric_id": 101, "cat_id": 1, "value": 10.0, "extra": "hacked"}
EOF

    # Generate Video Fixture
    ffmpeg -f lavfi -i "color=c=black:s=640x480" -vf "drawtext=text='CREATE TABLE categories (cat_id INT PRIMARY KEY, parent_id INT NULL REFERENCES categories(cat_id), name VARCHAR); CREATE TABLE metrics (metric_id INT PRIMARY KEY, cat_id INT REFERENCES categories(cat_id), value FLOAT);':fontcolor=white:fontsize=16:x=10:y=10" -frames:v 30 /app/schema_recording.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
