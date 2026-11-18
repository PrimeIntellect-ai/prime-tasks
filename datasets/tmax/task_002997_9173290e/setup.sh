#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        tesseract-ocr \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the dashboard screenshot
    convert -size 600x200 xc:white -fill black -pointsize 20 -annotate +20+40 "UPTIME MONITORING DASHBOARD\nSTATUS: OFFLINE\nPRIMARY SUBNET: 10.42.0.0/16\nCONTACT ADMIN FOR DETAILS" /app/dashboard_screenshot.png

    # Generate clean corpus
    for i in $(seq 1 20); do
        cat <<EOF > /app/corpus/clean/file_${i}.txt
ROUTE ADD 10.42.1.5 GW 10.42.0.1
ROUTE ADD 10.42.100.2 GW 10.42.0.254
ROUTE ADD 10.42.255.254 GW 10.42.1.1
EOF
    done

    # Generate evil corpus
    for i in $(seq 1 5); do
        cat <<EOF > /app/corpus/evil/malformed_${i}.txt
ROUTE ADD 10.42.1.1 GW 10.42.1
EOF
        cat <<EOF > /app/corpus/evil/oob_target_${i}.txt
ROUTE ADD 10.43.1.1 GW 10.42.0.1
EOF
        cat <<EOF > /app/corpus/evil/oob_gw_${i}.txt
ROUTE ADD 10.42.1.1 GW 192.168.1.1
EOF
        cat <<EOF > /app/corpus/evil/invalid_${i}.txt
ROUTE DELETE 10.42.1.1
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
