#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick git bc gawk fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate dashboard_alert.png
    convert -size 600x200 xc:white -fill black -pointsize 32 -gravity center -annotate +0+0 "FATAL_CODE: 0xDEAD_882A" /app/dashboard_alert.png

    # Generate monitor.dump
    dd if=/dev/urandom bs=1M count=5 | base64 > /app/monitor.dump
    echo "FATAL_CODE: 0xDEAD_882A ERROR_STATE PRECISION_THRESHOLD=0.000001" >> /app/monitor.dump
    dd if=/dev/urandom bs=1M count=5 | base64 >> /app/monitor.dump

    # Create oracle_uptime_calc
    cat << 'EOF' > /app/oracle_uptime_calc
#!/usr/bin/env python3
import sys
from decimal import Decimal, getcontext
getcontext().prec = 28
with open(sys.argv[1], 'r') as f:
    lines = f.read().strip().split('\n')
total = sum(int(x) for x in lines if x.strip())
days = len([x for x in lines if x.strip()])
ans = (Decimal(total) / Decimal(days * 86400)) * Decimal(100)
print(f"{ans:.6f}")
EOF
    chmod +x /app/oracle_uptime_calc

    # Create git repo
    mkdir -p /app/uptime-monitor
    cd /app/uptime-monitor
    git init
    git config user.name "SRE"
    git config user.email "sre@example.com"

    # Commit 1
    cat << 'EOF' > calc.sh
#!/bin/bash
total=0
count=0
while read -r line; do
    if [ -n "$line" ]; then
        total=$((total + line))
        count=$((count + 1))
    fi
done < "$1"
echo "scale=6; ($total * 100) / ($count * 86400)" | bc -l
EOF
    chmod +x calc.sh
    git add calc.sh
    git commit -m "Initial commit"

    # Commit 2
    echo "# This script calculates uptime" >> calc.sh
    git commit -am "Add comments"

    # Commit 3 (Bad commit)
    cat << 'EOF' > calc.sh
#!/bin/bash
# This script calculates uptime
total=0
count=0
while read -r line; do
    if [ -n "$line" ]; then
        total=$((total + line))
        count=$((count + 1))
    fi
done < "$1"
echo "scale=2; ($total * 100) / ($count * 86400)" | bc -l
EOF
    git commit -am "Change scale to 2"

    # Commit 4
    echo "# This script calculates the uptime" >> calc.sh
    git commit -am "Fix typo in comment"

    # Commit 5
    echo "# End of script" >> calc.sh
    git commit -am "Add end comment"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
