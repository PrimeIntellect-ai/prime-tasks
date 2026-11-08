#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gcc
    pip3 install pytest

    mkdir -p /app/clean /app/evil

    # Generate the sanction list image
    convert -size 200x200 xc:white -fill black -pointsize 24 -draw "text 10,30 '405' text 10,60 '819' text 10,90 '1002' text 10,120 '3319'" /app/sanction_list.png

    # Generate clean graph (4 hops from 405 to 819)
    cat << 'EOF' > /app/clean/graph1.csv
405,10,100.0
10,20,50.0
20,30,25.0
30,819,10.0
EOF

    # Generate evil graph (3 hops from 405 to 819)
    cat << 'EOF' > /app/evil/graph1.csv
405,10,100.0
10,20,50.0
20,819,25.0
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
