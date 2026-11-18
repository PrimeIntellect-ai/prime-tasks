#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick g++ fonts-dejavu-core
    pip3 install pytest

    # Create directories
    mkdir -p /app/specs
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate image
    convert -size 400x150 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'SALT: QX9_v2' text 20,90 'WINDOW: 3'" /app/specs/params.png

    # Populate clean corpus
    cat << 'EOF' > /app/corpora/clean/clean1.csv
1620000000,sensor_A,45.5
1620000005,sensor_B,120.0
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.csv
1620000060,sensor_A_1,0.0
EOF

    # Populate evil corpus
    cat << 'EOF' > /app/corpora/evil/evil1.csv
1620000000,sensor_A,-5.0
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.csv
1620000000,sensor-<script>,45.5
EOF

    cat << 'EOF' > /app/corpora/evil/evil3.csv
1620000000,sensor_C,9999.9
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
