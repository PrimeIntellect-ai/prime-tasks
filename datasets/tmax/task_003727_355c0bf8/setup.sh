#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr openssl golang imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    mkdir -p /tmp/setup/clean
    mkdir -p /tmp/setup/evil

    # Create benign files
    echo "user1_newpass123" > /tmp/setup/clean/user1.txt
    echo "secure_password_456" > /tmp/setup/clean/user2.txt
    echo "alphanumeric789" > /tmp/setup/clean/user3.txt
    echo "justletters" > /tmp/setup/clean/user4.txt
    echo "1234567890" > /tmp/setup/clean/user5.txt

    # Create malicious files
    echo "' OR 1=1 --" > /tmp/setup/evil/sqli1.txt
    echo "admin' #" > /tmp/setup/evil/sqli2.txt
    echo "<script>alert(1)</script>" > /tmp/setup/evil/xss1.txt
    echo "<img src=x onerror=alert(1)>" > /tmp/setup/evil/xss2.txt
    echo "; rm -rf /" > /tmp/setup/evil/cmd1.txt

    # Compress and encrypt
    cd /tmp/setup
    tar -czf payloads.tar.gz clean evil
    openssl enc -aes-256-cbc -pbkdf2 -in payloads.tar.gz -out /app/payloads.tar.gz.enc -pass pass:R0t4t10n_2024!

    # Generate image
    # Note: Imagemagick policy might block some operations, but simple text drawing usually works.
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 36 -fill black -draw "text 20,60 'R0t4t10n_2024!'" /app/master_pass.png

    # Cleanup setup files
    rm -rf /tmp/setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
