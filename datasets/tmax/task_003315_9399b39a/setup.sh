#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go espeak
    pip3 install pytest requests cryptography

    mkdir -p /app
    espeak -w /app/intercept.wav "System alert. The new admin token is omega seven delta. Ensure the firewall blocks all traffic to evilcorp dot local immediately."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
