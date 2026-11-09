#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pyinstaller Pillow

    mkdir -p /app
    mkdir -p /home/user/.config/systemd/user/

    # Create the reference legacy python script
    cat << 'EOF' > /tmp/legacy.py
import sys
import re
import json

if len(sys.argv) > 1:
    log_line = sys.argv[1]
    match = re.match(r"^\[(CRITICAL|ERROR)\] .* (ConnectionRefused|Timeout) \d+$", log_line)
    if match:
        reason = match.group(2)
        severity = 3 if reason == "Timeout" else 5
        alert = {
            "regex_match": True,
            "severity": severity,
            "destination": "alerting@internal.mail"
        }
        print(json.dumps(alert))
EOF

    # Compile it to a binary
    pyinstaller --onefile /tmp/legacy.py --distpath /app -n legacy_alert_parser.bin
    chmod +x /app/legacy_alert_parser.bin

    # Generate the screenshot using Pillow
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (1000, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = """ALERT CONFIGURATION:
Regex Filter: "^\[(CRITICAL|ERROR)\] .* (ConnectionRefused|Timeout) \d+$"
Severity Override: If "Timeout", severity=3; If "ConnectionRefused", severity=5.
Alert Destination: alerting@internal.mail"""
d.text((10,10), text, fill=(0,0,0))
img.save('/app/alert_rules_screenshot.png')
EOF
    python3 /tmp/gen_image.py

    # Create the dummy systemd service
    cat << 'EOF' > /home/user/.config/systemd/user/dummy-mail-relay.service
[Unit]
Description=Dummy Mail Relay

[Service]
ExecStart=/bin/true
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
