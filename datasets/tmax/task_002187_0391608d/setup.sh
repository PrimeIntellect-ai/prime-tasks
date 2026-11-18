#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y ffmpeg tesseract-ocr golang fonts-dejavu-core

    # Create the app directory
    mkdir -p /app

    # Generate the text file with the telemetry data
    python3 -c '
with open("telemetry.txt", "w") as f:
    for _ in range(10): f.write("[TELEMETRY] NODE:ALPH P:10.0 V:2.0 A:4.0\n\n")
    for _ in range(15): f.write("[TELEMETRY] NODE:BETA P:5.0 V:3.0 A:9.0\n\n")
    for _ in range(20): f.write("[TELEMETRY] NODE:GAMM P:2.5 V:4.0 A:1.0\n\n")
'

    # Create the scrolling video using ffmpeg
    ffmpeg -f lavfi -i color=c=black:s=800x600:d=30 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=telemetry.txt:fontcolor=white:fontsize=24:y=h-100*t" -c:v libx264 -pix_fmt yuv420p /app/telemetry_backup.mp4

    # Clean up temporary text file
    rm telemetry.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
