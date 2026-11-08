#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make cron imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app
    convert -background white -fill black -font Liberation-Sans -pointsize 24 label:"METRIC SERVICE SPEC\nPORT: 8085\nTOKEN: secr3t-auth-77X" /app/network_spec.png

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/src /home/user/bin
    chmod -R 777 /home/user
