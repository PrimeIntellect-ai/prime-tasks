#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        tesseract-ocr \
        sqlite3 \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app

    # Create legacy_nodes.db
    sqlite3 /app/legacy_nodes.db "CREATE TABLE nodes (id INTEGER PRIMARY KEY, label TEXT);"
    sqlite3 /app/legacy_nodes.db "INSERT INTO nodes (label) VALUES ('ALPHA'), ('BETA'), ('GAMMA'), ('DELTA'), ('EPSILON'), ('ZETA'), ('ETA'), ('THETA'), ('IOTA'), ('KAPPA');"

    # Create schema_edges.mp4
    ffmpeg -f lavfi -i "color=c=black:s=640x480:d=10:r=30" \
    -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='ALPHA->BETA':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,0,1)', \
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='BETA->GAMMA':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,1,2)', \
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='GAMMA->DELTA':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,2,3)', \
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='ALPHA->EPSILON':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,3,4)', \
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='EPSILON->ZETA':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,4,5)', \
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='ZETA->ETA':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,5,6)', \
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='ETA->THETA':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,6,7)', \
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='BETA->IOTA':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,7,8)', \
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='IOTA->KAPPA':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,8,9)', \
    drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='KAPPA->ALPHA':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,9,10)'" \
    -c:v libx264 -y /app/schema_edges.mp4

    # Create oracle_project_graph
    cat << 'EOF' > /app/oracle_project_graph
#!/usr/bin/env python3
import sys

edges = [
    ("ALPHA", "BETA"),
    ("BETA", "GAMMA"),
    ("GAMMA", "DELTA"),
    ("ALPHA", "EPSILON"),
    ("EPSILON", "ZETA"),
    ("ZETA", "ETA"),
    ("ETA", "THETA"),
    ("BETA", "IOTA"),
    ("IOTA", "KAPPA"),
    ("KAPPA", "ALPHA")
]

graph = {}
for u, v in edges:
    graph.setdefault(u, []).append(v)

def bfs(start, max_depth):
    visited = set([start])
    queue = [(start, 0)]
    while queue:
        node, depth = queue.pop(0)
        if depth < max_depth:
            for neighbor in graph.get(node, []):
                if neighbor not in visited:
                    visited.add(neighbor)
                    queue.append((neighbor, depth + 1))
    return visited

if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(1)
    node_label = sys.argv[1]
    max_depth = int(sys.argv[2])
    res = bfs(node_label, max_depth)
    print(",".join(sorted(res)))
EOF
    chmod +x /app/oracle_project_graph

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
