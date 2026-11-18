#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/config_dictation.wav "Add rule for IP 192.168.1.100 on port 80. Add rule for IP 10.5.5.1 on port 22. Remove rule for IP 192.168.1.100 on port 80. Add rule for IP 172.16.0.5 on port 443. Add rule for IP 10.5.5.1 on port 8080. Remove rule for IP 172.16.0.5 on port 443. Add rule for IP 192.168.1.200 on port 3306. Add rule for IP 192.168.1.200 on port 3306."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
