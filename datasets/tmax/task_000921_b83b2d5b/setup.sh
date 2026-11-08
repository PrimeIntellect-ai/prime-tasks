#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg podman rustc cargo
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil
    echo "Normal traffic from 192.168.1.5" > /app/corpus/clean/log1.txt
    echo -e "Connection spike\nIP 10.0.0.2: 40 connections" > /app/corpus/clean/log2.txt
    echo "TCP FIN wait" > /app/corpus/clean/log3.txt

    echo "Warning: UDP FLOOD detected on port 80" > /app/corpus/evil/log1.txt
    echo -e "Connection spike\nIP 192.168.1.100: 55 connections" > /app/corpus/evil/log2.txt
    echo "UDP FLOOD from unknown" > /app/corpus/evil/log3.txt

    ffmpeg -f lavfi -i color=c=black:s=320x240:d=5 -vf "drawbox=x=100:y=100:w=1:h=1:color=red:t=fill:enable='between(n,10,54)'" -c:v libx264 -y /app/router_diag.mp4
    chmod -R 755 /app/corpus /app/router_diag.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
