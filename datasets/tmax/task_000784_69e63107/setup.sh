#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip qrencode ffmpeg imagemagick zbar-tools g++
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Frame 1
    qrencode -o frame1.png '{"edges": [["db1", "db2", 15], ["db1", "db3", 10]]}'
    # Frame 2
    qrencode -o frame2.png '{"edges": [["db2", "db4", 25], ["db3", "db4", 5]]}'
    # Frame 3
    qrencode -o frame3.png '{"edges": [["db4", "db5", 30], ["db2", "db5", 20]]}'

    # Resize to ensure ffmpeg processes them nicely
    convert frame1.png -scale 400x400 frame1.png
    convert frame2.png -scale 400x400 frame2.png
    convert frame3.png -scale 400x400 frame3.png

    # Create video at 1 fps
    ffmpeg -y -framerate 1 -i frame%d.png -c:v libx264 -r 30 -pix_fmt yuv420p /app/backup_topology.mp4

    rm frame1.png frame2.png frame3.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
