#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y tesseract-ocr gcc imagemagick fonts-dejavu-core

    # Create directories
    mkdir -p /app /home/user

    # Create network.csv
    cat << 'EOF' > /home/user/network.csv
0,1,10
0,2,5
1,3,1
2,1,3
2,3,9
2,4,2
3,4,4
4,0,7
4,3,6
EOF

    # Create patch.png
    convert -size 200x100 xc:white -font DejaVu-Sans -pointsize 16 -fill black \
        -annotate +10+20 "2,1,2" \
        -annotate +10+40 "3,4,1" \
        -annotate +10+60 "4,5,3" \
        /app/patch.png

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
