#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y ffmpeg zbar-tools qrencode imagemagick

    # Create directories
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean
    mkdir -p /tmp/frames

    # Generate evil corpus
    echo "<script>alert(1)</script>" > /app/corpus/evil/evil1.txt
    echo "admin' OR 1=1--" > /app/corpus/evil/evil2.txt
    echo "\"><svg/onload=prompt(1)>" > /app/corpus/evil/evil3.txt

    # Generate clean corpus
    echo "<b>Hello</b>" > /app/corpus/clean/clean1.txt
    echo "john_doe" > /app/corpus/clean/clean2.txt
    echo "Just a normal text message." > /app/corpus/clean/clean3.txt

    # Generate frames for the video
    for i in $(seq -w 0 9); do
        convert -size 400x400 xc:black /tmp/frames/frame_$i.png
    done

    # Generate QR codes for specific frames
    qrencode -s 10 -o /tmp/frames/frame_02.png "<sCrIpt>alert(document.domain)</script>"
    qrencode -s 10 -o /tmp/frames/frame_05.png "admin' OR 1=1--"
    qrencode -s 10 -o /tmp/frames/frame_08.png "\"><svg/onload=prompt(1)>"

    # Compile video
    ffmpeg -framerate 1 -i /tmp/frames/frame_%02d.png -c:v libx264 -r 30 -pix_fmt yuv420p /app/evidence.mp4

    # Clean up frames
    rm -rf /tmp/frames

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
