#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest pillow

    mkdir -p /app

    # Create the oracle script
    cat << 'EOF' > /app/oracle_token.py
#!/usr/bin/env python3
import sys

def generate_token(service_name, timestamp):
    rev_name = service_name[::-1]
    ts_mult = int(timestamp) * 3
    token = f"{rev_name}-{ts_mult}"
    if service_name.startswith("db"):
        token += "-admin"
    return token

if __name__ == "__main__":
    print(generate_token(sys.argv[1], sys.argv[2]))
EOF
    chmod +x /app/oracle_token.py

    # Generate the token rules image
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw, ImageFont

img = Image.new('RGB', (1000, 500), color=(255, 255, 255))
d = ImageDraw.Draw(img)

text = """BACKUP VAULT TOKEN GENERATION RULES
Input arguments: SERVICE_NAME (string), TIMESTAMP (integer)

Step 1: Reverse the string SERVICE_NAME.
Step 2: Multiply the TIMESTAMP by 3.
Step 3: Concatenate the results of Step 1 and Step 2, separated by a hyphen (-).
Step 4: If the original SERVICE_NAME begins with the exact prefix "db" (case-sensitive), append the string "-admin" to the end of the concatenated result.

Output the final string."""

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 20)
except IOError:
    font = ImageFont.load_default()

d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/token_rules.png')
EOF

    python3 /tmp/make_image.py
    rm /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
