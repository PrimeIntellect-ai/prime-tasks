#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y imagemagick tesseract-ocr fonts-dejavu cargo rustc

    # Create /app directory
    mkdir -p /app

    # Generate the compliance rule image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,40 'MIN_IN_DEGREE=3'" -draw "text 10,80 'MIN_SUM=500'" /app/compliance_rule.png

    # Create the oracle script
    cat << 'EOF' > /app/oracle_audit
#!/usr/bin/env python3
import sys
from collections import defaultdict

def main():
    in_edges = defaultdict(set)
    in_sum = defaultdict(int)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        parts = line.split(',')
        if len(parts) == 3:
            sender, receiver, amount_str = parts
            try:
                amount = int(amount_str)
                in_edges[receiver].add(sender)
                in_sum[receiver] += amount
            except ValueError:
                pass

    flagged = []
    for node in in_sum:
        if len(in_edges[node]) >= 3 and in_sum[node] >= 500:
            flagged.append(node)

    for node in sorted(flagged):
        print(node)

if __name__ == '__main__':
    main()
EOF

    chmod +x /app/oracle_audit

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
