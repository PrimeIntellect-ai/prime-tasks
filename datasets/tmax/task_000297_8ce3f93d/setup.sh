#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr python3-pil fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Create the image using Python and PIL to avoid ImageMagick policy issues
    cat << 'EOF' > /app/create_image.py
from PIL import Image, ImageDraw, ImageFont

text = """STREAMING DOC PROCESSOR RULES:
1. Read input from stdin and write to stdout.
2. For each line: If the line starts with exactly 'CMD: ', convert the entire line to uppercase.
3. For each line: If the line contains the exact substring 'TODO', drop the line entirely (do not output it).
4. For all other lines, output them exactly as they are.
5. After all lines are processed, output a final line exactly formatted as: 'MANIFEST: <SHA1>' where <SHA1> is the hexadecimal SHA-1 checksum of the entire original, unmodified standard input."""

font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16)
img = Image.new('RGB', (1000, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0), font=font)
img.save('/app/doc_rules.png')
EOF
    python3 /app/create_image.py
    rm /app/create_image.py

    # Create the oracle script
    cat << 'EOF' > /app/oracle_processor.py
import sys
import hashlib

def main():
    raw_data = sys.stdin.buffer.read()
    text = raw_data.decode('utf-8', errors='replace')

    lines = text.split('\n')
    # handle the case where split creates an extra empty line if the file ends with \n
    # but we should process line by line as splitlines(True) keeps the \n

    sha1 = hashlib.sha1(raw_data).hexdigest()

    # We will iterate line by line, preserving the original line endings
    import io
    reader = io.StringIO(text)

    for line in reader:
        if 'TODO' in line:
            continue
        if line.startswith('CMD: '):
            sys.stdout.write(line.upper())
        else:
            sys.stdout.write(line)

    # Add newline if the last line didn't have one, before printing manifest? 
    # The rule says: "After all lines are processed, output a final line exactly formatted as..."
    # Let's ensure MANIFEST is on its own line.
    if text and not text.endswith('\n'):
        sys.stdout.write('\n')
    sys.stdout.write(f"MANIFEST: {sha1}\n")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
