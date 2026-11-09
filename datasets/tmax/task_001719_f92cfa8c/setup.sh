#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang
    pip3 install --default-timeout=100 pytest Pillow

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the image using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 600), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''PORT_ALPHA->PORT_BETA
PORT_BETA->PORT_GAMMA
PORT_GAMMA->PORT_DELTA
PORT_DELTA->PORT_ALPHA
PORT_ALPHA->PORT_GAMMA
PORT_EPSILON->PORT_ZETA
PORT_ZETA->PORT_ALPHA'''
d.text((20, 20), text, fill=(0, 0, 0))
img.save('/app/hub_graph.png')
    "

    # Populate clean corpus
    cat << 'EOF' > /app/corpora/clean/test1.txt
PORT_ALPHA,PORT_BETA,PORT_GAMMA
PORT_EPSILON,PORT_ZETA,PORT_ALPHA,PORT_GAMMA
EOF

    cat << 'EOF' > /app/corpora/clean/test2.txt
PORT_GAMMA,PORT_DELTA,PORT_ALPHA,PORT_BETA
EOF

    # Populate evil corpus
    cat << 'EOF' > /app/corpora/evil/test1.txt
PORT_ALPHA,PORT_DELTA
EOF

    cat << 'EOF' > /app/corpora/evil/test2.txt
PORT_BETA,PORT_ZETA
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
