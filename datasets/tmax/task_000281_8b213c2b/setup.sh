#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends python3 python3-pip ffmpeg gcc tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/clean1.cql
MATCH (c:Customer)-[:PURCHASED]->(p:Product) RETURN c, p
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.cql
MATCH (c1:Customer)-[:KNOWS*1..3]->(c2:Customer) RETURN c1, c2
EOF

    cat << 'EOF' > /app/corpus/evil/evil1.cql
MATCH (c:Customer)-[:KNOWS*1..5]->(c2:Customer) RETURN c2
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.cql
MATCH (p:Product)-[:PURCHASED]->(c:Customer) RETURN p
EOF

    cat << 'EOF' > /app/corpus/evil/evil3.cql
MATCH (c:Company)-[:MANUFACTURED_BY]->(p:Product) RETURN c
EOF

    cat << 'EOF' > /app/corpus/evil/evil4.cql
MATCH (c:Customer)-[:LIKES]->(p:Product) RETURN c
EOF

    cat << 'EOF' > /tmp/make_video.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 600), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = "MAX_DEPTH=4\nALLOWED SCHEMA:\n(Customer)-[:PURCHASED]->(Product)\n(Product)-[:MANUFACTURED_BY]->(Company)\n(Customer)-[:KNOWS]->(Customer)"
d.text((10,10), text, fill=(0,0,0))
img.save('/tmp/frame.png')
EOF

    python3 /tmp/make_video.py
    ffmpeg -loop 1 -i /tmp/frame.png -c:v libx264 -t 5 -pix_fmt yuv420p /app/schema_meeting.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
