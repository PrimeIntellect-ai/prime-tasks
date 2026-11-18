#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg iptables expect
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the /app directory
    mkdir -p /app

    # Generate the audio file
    espeak -w /app/noc_report.wav "Emergency broadcast. We are seeing lateral movement. Please update the firewall to drop all traffic from the following malicious IPs: 10.5.12.4, 192.168.100.52, and 172.16.8.88. I repeat, block ten dot five dot twelve dot four, one ninety two dot one sixty eight dot one hundred dot fifty two, and one seventy two dot sixteen dot eight dot eighty eight. End of report."

    # Ensure permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
