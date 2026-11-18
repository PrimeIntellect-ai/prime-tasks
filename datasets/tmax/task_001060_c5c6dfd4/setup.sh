#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest pytesseract Pillow

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /app/test_data

    # Create the calibration image
    # Temporarily modify ImageMagick policy to allow text rendering if needed, though usually fine for basic text
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 20,50 'Factory Calibration Offset'" \
        -draw "text 20,100 'OFFSET=7.31'" \
        -draw "text 20,150 'Approved by QA'" \
        /app/calibration.png

    # Create clean data
    cat << 'EOF' > /app/corpora/clean/clean1.csv
timestamp,sensor_id,value
2023-10-12T14:30:00Z,A1B2C3D4,25.5
2023-10-12T14:35:00Z,X9Y8Z7W6,-10.0
EOF

    # Create evil data
    cat << 'EOF' > /app/corpora/evil/evil1.csv
timestamp,sensor_id,value
2023/10/12 14:30:00,A1B2C3D4,25.5
2023-10-12T14:30:00Z,SHORT,25.5
2023-10-12T14:30:00Z,A1B2C3D4,200.0
2023-10-12T14:30:00Z,A1B2C3D4,DROP TABLE sensors;
EOF

    # Create test data
    cat << 'EOF' > /app/test_data/test1.csv
timestamp,sensor_id,value
2023-10-12T14:30:00Z,A1B2C3D4,10.0
2023-10-12T14:35:00Z,A1B2C3D4,20.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
