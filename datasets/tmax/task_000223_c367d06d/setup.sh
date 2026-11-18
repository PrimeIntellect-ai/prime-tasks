#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pillow pytesseract

    mkdir -p /app
    cat << 'EOF' > /app/oracle.py
import sys
import json
import re

def process(line):
    try:
        data = json.loads(line)
        msg = data.get("message", "")
    except Exception:
        return ""

    # 1. Decode double-escaped unicode
    msg = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), msg)

    # 2 & 3. Replacements
    msg = msg.replace('@', 'AT').replace('#', 'HASH')

    # 4. Lowercase
    msg = msg.lower()

    # 5. Split on whitespace
    tokens = msg.split()

    # 6. Filter alphanumeric
    valid_tokens = [t for t in tokens if t.isalnum()]

    # 7. Unique and sort
    sorted_tokens = sorted(list(set(valid_tokens)))

    # 8. Join
    return '|'.join(sorted_tokens)

if __name__ == "__main__":
    input_data = sys.stdin.read().strip()
    if input_data:
        print(process(input_data), end="")
EOF
    chmod +x /app/oracle.py

    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw

text = """Normalization Pipeline:
1. Decode double-escaped unicode sequences (e.g., \\uXXXX to the actual character).
2. Replace all instances of '@' with 'AT'.
3. Replace all instances of '#' with 'HASH'.
4. Convert the string to lowercase.
5. Tokenize by splitting on whitespace.
6. Filter out any tokens that contain non-alphanumeric characters.
7. Sort the unique tokens alphabetically.
8. Join the sorted tokens using the pipe character '|' and output the result."""

img = Image.new('RGB', (800, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/mapping.png')
EOF
    python3 /tmp/gen_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
