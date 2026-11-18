#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak-ng -w /app/incident_dictation.wav "Compliance log entry. We detected an attack from IP address 10.55.20.156. The payload was encoded in base 64 as follows: b H M g L W x h I C 9 l d G M v c G F z c 3 d k. This exploit is categorized under CWE 78. Please update the firewall policy to drop all tcp traffic from this IP address on port 443."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
