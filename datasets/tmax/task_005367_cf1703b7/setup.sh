#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang zip imagemagick fonts-liberation tar
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Generate auth token image
    convert -size 400x100 xc:white -font Liberation-Sans -pointsize 24 -fill black -gravity center -draw "text 0,0 'AUTH-TOKEN-77X9-B2C4'" auth_token.png

    # Generate logs_2022.zip
    mkdir -p logs_2022
    dd if=/dev/urandom of=logs_2022/syslog.log bs=1 count=15432
    dd if=/dev/urandom of=logs_2022/auth.log bs=1 count=85000
    cd logs_2022 && zip ../logs_2022.zip syslog.log auth.log && cd ..

    # Generate logs_2023.zip
    mkdir -p logs_2023
    dd if=/dev/urandom of=logs_2023/app.log bs=1 count=210000
    dd if=/dev/urandom of=logs_2023/db.dump bs=1 count=750000
    dd if=/dev/urandom of=logs_2023/cache.dat bs=1 count=5000
    cd logs_2023 && zip ../logs_2023.zip app.log db.dump cache.dat && cd ..

    # Create tar.gz
    tar -czvf server_backup.tar.gz logs_2022.zip logs_2023.zip

    # Cleanup
    rm -rf logs_2022 logs_2023 logs_2022.zip logs_2023.zip

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
