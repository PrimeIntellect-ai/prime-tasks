#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        jq \
        tar \
        imagemagick \
        fonts-dejavu-core \
        wget

    pip3 install pytest yq

    mkdir -p /app/configs

    # Create 100 JSON files
    for i in $(seq 1 100); do
        echo '{"id": '$i', "data": "'$RANDOM'"}' > /app/configs/config_$i.json
    done

    # Inject "backup_enabled": true into specific files ensuring size between 50 and 2048 bytes
    for i in 3 12 45 88 91; do
        echo '{"id": '$i', "backup_enabled": true, "data": "some padding data to make it larger than 50 bytes..."}' > /app/configs/config_$i.json
    done

    # Create a file < 50 bytes with backup_enabled: true
    echo '{"backup_enabled":true}' > /app/configs/config_10.json

    # Create a file > 2048 bytes with backup_enabled: true
    PAD=$(head -c 2500 < /dev/zero | tr '\0' 'a')
    echo '{"id": 20, "backup_enabled": true, "pad": "'$PAD'"}' > /app/configs/config_20.json

    # Generate the rules image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 14 -fill black -annotate +10+20 "TARGET_DIR=/app/configs\nMIN_SIZE=50 bytes\nMAX_SIZE=2048 bytes\nEXTENSION=.json\nMUST CONTAIN KEY: \"backup_enabled\": true" /app/rules.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
