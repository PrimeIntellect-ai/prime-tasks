#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    convert -size 400x300 xc:white -font DejaVu-Sans -pointsize 16 -fill black -annotate +20+40 "ARCHITECTURE SPECIFICATIONS\n-------------------------\nPROXY_PORT: 8080\nAPP_1_PORT: 8081\nAPP_2_PORT: 8082\nMONITOR_PORT: 9090\nAUTH_TOKEN: SecretMonitor77\nTHRESHOLD: 4" /app/architecture_spec.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
