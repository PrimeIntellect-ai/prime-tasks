#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        cargo \
        rustc \
        curl \
        build-essential

    pip3 install pytest

    mkdir -p /app

    # Generate the target_node.png image
    convert -size 200x50 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,35 'N-8392'" /app/target_node.png

    # Create network.csv
    cat << 'EOF' > /app/network.csv
src,dst
N-8392,N-1000
N-1000,N-2000
N-1000,N-3000
N-2000,N-4000
N-5000,N-8392
N-3000,N-4000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
