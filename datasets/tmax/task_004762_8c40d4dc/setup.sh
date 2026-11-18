#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        gawk \
        bc \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest pandas numpy

    mkdir -p /app

    cat << 'EOF' > /app/table_a.tsv
ID	F1	F2
1	10	20
2	15	10
3	8	12
4	20	5
5	12	18
EOF

    cat << 'EOF' > /app/table_b.csv
ID,F3
1,5
2,8
3,3
4,12
5,7
EOF

    # Generate the image
    convert -size 400x300 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 20,40 'PRIOR_A: 0.35\nPRIOR_B: 0.65\nW1: 1.5\nW2: -0.5\nW3: 2.0'" \
        /app/config_matrix.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
