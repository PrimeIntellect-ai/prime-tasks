#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        cargo \
        rustc

    pip3 install pytest Pillow cryptography

    mkdir -p /app

    # Generate the legacy_key.png and db_backup.enc
    python3 -c '
from PIL import Image, ImageDraw
import hashlib
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# Generate image
img = Image.new("RGB", (200, 50), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "WntrBse_", fill=(0, 0, 0))
img.save("/app/legacy_key.png")

# Encrypt backup
key = hashlib.sha256(b"WntrBse_xk").digest()
aesgcm = AESGCM(key)
nonce = b"0" * 12
data = b"{\"db_user\":\"admin\",\"db_pass\":\"sUp3rS3cr3tDBP@ss\"}"
ct = aesgcm.encrypt(nonce, data, None)

with open("/app/db_backup.enc", "wb") as f:
    f.write(ct)
'

    # Create old_service.sh
    cat << 'EOF' > /app/old_service.sh
#!/bin/bash
# Legacy service launcher
DB_PASS=$(cat /etc/secret_db_pass)
/usr/bin/db_client --host=localhost --user=admin --password="${DB_PASS}" --daemon
EOF
    chmod +x /app/old_service.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
