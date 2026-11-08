#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pyinstaller Pillow

    mkdir -p /app

    # Create oracle binary
    cat << 'EOF' > /tmp/oracle.py
import sys, base64

def main():
    if len(sys.argv) < 2:
        return
    try:
        data = base64.b64decode(sys.argv[1])
    except:
        print("ERROR: INVALID_HEADER")
        sys.exit(1)

    if not data.startswith(b"CALC_V2!"):
        print("ERROR: INVALID_HEADER")
        sys.exit(1)

    if len(data) < 11:
        print("ERROR: UNKNOWN_OPCODE")
        sys.exit(1)

    opcode = data[8]
    if opcode not in (0x10, 0x20, 0x30):
        print("ERROR: UNKNOWN_OPCODE")
        sys.exit(1)

    length = (data[9] << 8) | data[10]
    payload = data[11:11+length].decode('ascii', errors='ignore')

    try:
        ints = [int(x) for x in payload.split()]
    except:
        ints = []

    if not ints:
        print(0)
        sys.exit(0)

    res = ints[0]
    for val in ints[1:]:
        if opcode == 0x10:
            res += val
        elif opcode == 0x20:
            res -= val
        elif opcode == 0x30:
            res *= val

    print(res)
    sys.exit(0)

if __name__ == "__main__":
    main()
EOF

    cd /tmp
    pyinstaller --onefile oracle.py
    mv dist/oracle /app/oracle_bin
    chmod +x /app/oracle_bin

    # Create format image
    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """MAGIC HEADER = "CALC_V2!"
OPCODES:
0x10 -> ADD
0x20 -> SUBTRACT
0x30 -> MULTIPLY
Payload: ints separated by space."""
d.text((10,10), text, fill=(0,0,0))
img.save('/app/format.png')
EOF
    python3 /tmp/make_img.py

    # Clean up
    rm -rf /tmp/oracle.py /tmp/make_img.py /tmp/build /tmp/dist /tmp/oracle.spec

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
