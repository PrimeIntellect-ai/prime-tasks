#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tcpdump
    pip3 install pytest scapy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate incident.mp4 with frame 74 black and malicious metadata
    ffmpeg -f lavfi -i color=c=white:s=320x240:r=30:d=5 -vf "drawbox=x=0:y=0:w=320:h=240:color=black:t=fill:enable='eq(n,74)'" -c:v libx264 -metadata comment="-2147483648" -y /app/incident.mp4

    # Generate clean corpus
    for i in $(seq 1 10); do
        ffmpeg -f lavfi -i color=c=blue:s=320x240:r=30:d=1 -c:v libx264 -metadata comment="safe_$i" -y /app/corpus/clean/clean_$i.mp4
    done

    # Generate evil corpus
    for i in $(seq 1 10); do
        ffmpeg -f lavfi -i color=c=red:s=320x240:r=30:d=1 -c:v libx264 -metadata comment="-2147483648" -y /app/corpus/evil/evil_$i.mp4
    done

    # Generate mock pcap file
    python3 -c "
from scapy.all import IP, TCP, Raw, wrpcap
pkt = IP(dst='10.0.0.2')/TCP(dport=80)/Raw(load='POST /upload HTTP/1.1\r\nHost: example.com\r\nX-Video-Offset: -2147483648\r\n\r\n')
wrpcap('/app/traffic.pcap', [pkt])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
