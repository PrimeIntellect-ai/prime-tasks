#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip qrencode ffmpeg openssl zbar-tools
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Generate encrypted data
    DATA=$(echo -n "PORT=9090;TOKEN=TangoDown;PAYLOAD=Invoke-Evasion" | openssl enc -aes-256-cbc -pbkdf2 -a -salt -pass pass:8492 | tr -d '\n')

    # Create QR text
    echo "HASH:c52e6d1c81525cb741910ee24aa86ebbcbb656715f5fc8cd2aa6e944de88d1d8" > qr.txt
    echo "DATA:${DATA}" >> qr.txt

    # Generate QR image
    qrencode -o qr.png -s 10 < qr.txt

    # Create video, ensuring dimensions are even to prevent libx264 errors
    ffmpeg -loop 1 -i qr.png -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -t 1 -pix_fmt yuv420p /app/intercept.mp4

    # Cleanup
    rm qr.png qr.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
