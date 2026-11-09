#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        unzip \
        zip \
        socat \
        openssl \
        jq \
        imagemagick \
        fonts-liberation \
        curl \
        wget

    pip3 install pytest

    # Create evidence image
    mkdir -p /app
    convert -background white -fill black -font Liberation-Mono -pointsize 36 label:"CORP_SEC" /app/evidence.png

    # Create secret data, hash, and vault
    mkdir -p /home/user
    echo -n "FLAG{f0r3ns1cs_w1n}" > /home/user/secret_data.txt
    sha256sum /home/user/secret_data.txt | awk '{print $1}' > /home/user/hash.txt

    # Zip it with password and remove the original
    cd /home/user
    zip -P CORP_SEC_42 vault.zip secret_data.txt
    rm secret_data.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
