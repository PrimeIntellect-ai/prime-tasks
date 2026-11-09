#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest pycryptodome Pillow

mkdir -p /app/evidence

cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = "You have been compromised.\nMASTER_KEY: 7c5a9b8e2f1d4a6c3b8e9f0d1a2b3c4d\nSALT: S4LT_S3CR3T_99"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/evidence/ransom_note.png')
EOF

python3 /tmp/gen_image.py

cat << 'EOF' > /app/oracle_decoder
#!/usr/bin/env python3
import sys
import hashlib
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad
import binascii

def main():
    raw_http = sys.stdin.read()
    if not raw_http.strip():
        print("MALFORMED_REQUEST", end="")
        return

    headers_part, _, body = raw_http.partition('\r\n\r\n')
    if not body:
        headers_part, _, body = raw_http.partition('\n\n')

    headers = headers_part.split('\n')

    session_id = None
    token = None

    for line in headers:
        line = line.strip()
        if line.lower().startswith('cookie:'):
            cookies = line[7:].split(';')
            for c in cookies:
                if '=' in c:
                    k, v = c.split('=', 1)
                    if k.strip().lower() == 'session-id':
                        session_id = v.strip()
        elif line.lower().startswith('x-ransom-token:'):
            token = line[15:].strip()

    if not session_id or not token or not body.strip():
        print("MALFORMED_REQUEST", end="")
        return

    salt = "S4LT_S3CR3T_99"
    expected_token = hashlib.md5((session_id + salt).encode()).hexdigest().lower()

    if token.lower() != expected_token:
        print("INVALID_TOKEN", end="")
        return

    key = bytes.fromhex("7c5a9b8e2f1d4a6c3b8e9f0d1a2b3c4d")
    iv = hashlib.md5(session_id.encode()).digest()

    try:
        ciphertext = bytes.fromhex(body.strip())
        cipher = AES.new(key, AES.MODE_CBC, iv)
        plaintext = unpad(cipher.decrypt(ciphertext), AES.block_size)
        print(plaintext.decode('utf-8'), end="")
    except Exception:
        print("DECRYPTION_ERROR", end="")

if __name__ == '__main__':
    main()
EOF

chmod +x /app/oracle_decoder

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
