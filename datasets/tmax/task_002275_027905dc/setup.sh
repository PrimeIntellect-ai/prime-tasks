#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest Pillow

mkdir -p /app

# Generate the format_spec.png image
cat << 'EOF' > /app/generate_image.py
from PIL import Image, ImageDraw

text = """ARCHIVE FORMAT SPECIFICATION:
1. MAGIC HEADER: 4 bytes 'BKP9'
2. OBFUSCATION: Each subsequent byte is XOR'ed with the key 115
3. COMPRESSION: The de-obfuscated bytes form a standard zlib stream"""

# Create a white image
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/format_spec.png')
EOF

python3 /app/generate_image.py
rm /app/generate_image.py

# Create the oracle script
cat << 'EOF' > /app/oracle.py
import sys
import zlib

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    with open(sys.argv[1], 'rb') as f:
        data = f.read()

    if not data.startswith(b"BKP9"):
        sys.stderr.write("Invalid magic header\n")
        sys.exit(1)

    payload = data[4:]
    deobfuscated = bytes([b ^ 115 for b in payload])
    decompressed = zlib.decompress(deobfuscated)

    sys.stdout.buffer.write(decompressed)

if __name__ == "__main__":
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
