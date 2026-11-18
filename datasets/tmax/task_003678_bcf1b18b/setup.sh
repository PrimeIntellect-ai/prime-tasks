#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
    pip3 install pytest

    mkdir -p /app/taxonomy_corpus/clean
    mkdir -p /app/taxonomy_corpus/evil

    # Generate dummy video
    ffmpeg -y -f lavfi -i testsrc=duration=2:size=320x240:rate=30 -c:v libx264 -g 15 /app/foraging_behavior.mp4

    # Generate clean corpus files
    cat << 'EOF' > /app/taxonomy_corpus/clean/tree1.json
[
    {"id": 1, "parent_id": null},
    {"id": 2, "parent_id": 1},
    {"id": 3, "parent_id": 1},
    {"id": 4, "parent_id": 2}
]
EOF

    cat << 'EOF' > /app/taxonomy_corpus/clean/tree2.json
[
    {"id": 10, "parent_id": null},
    {"id": 20, "parent_id": 10}
]
EOF

    # Generate evil corpus files
    cat << 'EOF' > /app/taxonomy_corpus/evil/cycle1.json
[
    {"id": 1, "parent_id": 2},
    {"id": 2, "parent_id": 3},
    {"id": 3, "parent_id": 1}
]
EOF

    cat << 'EOF' > /app/taxonomy_corpus/evil/cycle2.json
[
    {"id": 10, "parent_id": 10}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
