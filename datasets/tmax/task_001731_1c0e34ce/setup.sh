#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg jq
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate clean JSON graphs
    cat << 'EOF' > /app/corpora/clean/clean1.json
{
  "nodes": [
    {"id": "n1", "indexed": true, "idx_key": "x"},
    {"id": "n2"}
  ],
  "edges": [
    {"source": "n1", "target": "n2", "weight": 5}
  ]
}
EOF

    # Generate evil JSON graphs
    cat << 'EOF' > /app/corpora/evil/evil1.json
{
  "nodes": [{"id": "n1"}],
  "edges": [{"source": "n1", "target": "n2", "weight": -1}]
}
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.json
{
  "nodes": [{"id": "n1'; DROP TABLE;"}],
  "edges": []
}
EOF

    cat << 'EOF' > /app/corpora/evil/evil3.json
{
  "nodes": [{"id": "n1", "indexed": true}],
  "edges": []
}
EOF

    cat << 'EOF' > /app/corpora/evil/evil4.json
{"nodes": [{"id": "n1",]}
EOF

    # Create an MP4 file with exactly 14 I-frames
    ffmpeg -f lavfi -i testsrc=duration=14:rate=1 -g 1 -c:v libx264 /app/network_simulation.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
