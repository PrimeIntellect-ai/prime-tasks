#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install --default-timeout=100 pytest Pillow

    mkdir -p /app/data/clean /app/data/evil

    # Clean 1: Valid path of length 4
    cat << 'EOF' > /app/data/clean/graph1.txt
GENE G1 TRANSCRIPT T1
TRANSCRIPT T1 PROTEIN P1
PROTEIN P1 COMPLEX C1
COMPLEX C1 PATHWAY PW1
EOF

    # Evil 1: Invalid transition
    cat << 'EOF' > /app/data/evil/graph1.txt
GENE G1 PROTEIN P1
PROTEIN P1 COMPLEX C1
COMPLEX C1 PATHWAY PW1
EOF

    # Evil 2: No valid path to PATHWAY
    cat << 'EOF' > /app/data/evil/graph2.txt
GENE G1 TRANSCRIPT T1
TRANSCRIPT T1 PROTEIN P1
PROTEIN P1 METABOLITE M1
EOF

    # Generate the image
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """VALID TRANSITIONS:
GENE -> TRANSCRIPT
TRANSCRIPT -> PROTEIN
PROTEIN -> METABOLITE
METABOLITE -> PATHWAY
PROTEIN -> COMPLEX
COMPLEX -> PATHWAY
MAXIMUM PATH LENGTH: 4"""
d.text((10,10), text, fill=(0,0,0))
img.save('/app/pathway_schema.png')
EOF
    python3 /tmp/gen_image.py
    rm /tmp/gen_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
