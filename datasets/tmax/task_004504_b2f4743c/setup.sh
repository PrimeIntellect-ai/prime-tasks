#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest pycryptodome Pillow

mkdir -p /app

cat << 'EOF' > /tmp/setup.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "POLICY_KEY: CorpPolicySecu**", fill=(0,0,0))
img.save('/app/policy_doc.png')

import hmac, hashlib
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad
import binascii

key = b'CorpPolicySecuXY'
iv = b'1234567890123456'
plaintext = b'VALID_DEVSECOPS_TEST'

cipher = AES.new(key, AES.MODE_CBC, iv)
ciphertext = cipher.encrypt(pad(plaintext, AES.block_size))

mac = hmac.new(key, iv + ciphertext, hashlib.sha256).digest()
payload_raw = iv + mac + ciphertext
with open('/app/test_payload.hex', 'w') as f:
    f.write(binascii.hexlify(payload_raw).decode('utf-8'))
EOF

python3 /tmp/setup.py

cat << 'EOF' > /app/oracle.py
import sys, binascii, hmac, hashlib
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

def main():
    if len(sys.argv) != 2:
        print("ERROR: INVALID_FORMAT")
        sys.exit(1)

    hex_str = sys.argv[1]
    try:
        raw_bytes = binascii.unhexlify(hex_str)
    except:
        print("ERROR: INVALID_FORMAT")
        sys.exit(1)

    if len(raw_bytes) < 64:
        print("ERROR: INVALID_FORMAT")
        sys.exit(1)

    iv = raw_bytes[0:16]
    provided_mac = raw_bytes[16:48]
    ciphertext = raw_bytes[48:]

    key = b'CorpPolicySecuXY'

    expected_mac = hmac.new(key, iv + ciphertext, hashlib.sha256).digest()
    if not hmac.compare_digest(expected_mac, provided_mac):
        print("ERROR: INTEGRITY_VIOLATION")
        sys.exit(2)

    try:
        cipher = AES.new(key, AES.MODE_CBC, iv)
        plaintext = unpad(cipher.decrypt(ciphertext), AES.block_size)
        sys.stdout.buffer.write(plaintext)
        sys.exit(0)
    except Exception:
        print("ERROR: DECRYPTION_FAILED")
        sys.exit(3)

if __name__ == '__main__':
    main()
EOF

chmod 755 /app/oracle.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
