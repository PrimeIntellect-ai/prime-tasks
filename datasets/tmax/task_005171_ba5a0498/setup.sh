#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/q1.cypher
MATCH (n:User)-[:POSTED]->(p:Post) RETURN n, p
EOF
    cat << 'EOF' > /app/corpus/clean/q2.cypher
MATCH (a) RETURN a LIMIT 10
EOF

    cat << 'EOF' > /app/corpus/evil/e1.cypher
MATCH (a:User), (b:Post) RETURN a, b
EOF
    cat << 'EOF' > /app/corpus/evil/e2.cypher
MATCH (a)-[:KNOWS]->(b), (c) RETURN a, b, c
EOF

    # Generate a 5-second video with the secret node ID appearing at 4 seconds
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=text='NODE_ID_8192':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,4,5)'" -c:v libx264 -pix_fmt yuv420p /app/graph_record.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
