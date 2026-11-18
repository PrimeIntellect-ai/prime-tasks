#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Create the oracle parser
    cat << 'EOF' > /app/oracle_parser
#!/usr/bin/env python3
import sys
import json

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
        if not all(k in data for k in ("timestamp", "severity", "source", "message")):
            print("INVALID_LOG")
            continue
        sev = int(data["severity"])
        if sev >= 90:
            sev_str = "FATAL"
        elif sev >= 70:
            sev_str = "HIGH"
        elif sev >= 30:
            sev_str = "MEDIUM"
        else:
            sev_str = "LOW"
        print(f"[{sev_str}] {data['source']} - {data['timestamp']} : {data['message']}")
    except Exception:
        print("INVALID_LOG")
EOF
    chmod +x /app/oracle_parser

    # Create the alert rules text file
    cat << 'EOF' > /tmp/rules.txt
ALERT PARSING RULES

Thresholds:
Severity >= 90: FATAL
Severity >= 70 and < 90: HIGH
Severity >= 30 and < 70: MEDIUM
Severity < 30: LOW

Output Format string:
[<SEVERITY>] <source> - <timestamp> : <message>
EOF

    # Fix ImageMagick policy to allow text to image
    sed -i 's/<policy domain="path" rights="none" pattern="@\*"/<policy domain="path" rights="read" pattern="@\*"/g' /etc/ImageMagick-6/policy.xml || true

    # Generate the image
    convert -background white -fill black -font DejaVu-Sans -pointsize 20 label:@/tmp/rules.txt /app/alert_rules.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
