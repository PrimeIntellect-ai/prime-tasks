#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/graph.txt
ALPHA -> BETA
ALPHA -> GAMMA
BETA -> DELTA
BETA -> OMEGA
GAMMA -> DELTA
THETA -> RHO
RHO -> OMEGA
DELTA -> OMEGA
EOF

    # Use ImageMagick to create the image
    convert -background white -fill black -font Liberation-Mono -pointsize 24 label:"$(cat /app/graph.txt)" /app/dataset_lineage.png
    rm /app/graph.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
