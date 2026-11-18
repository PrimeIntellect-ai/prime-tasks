#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create encoder.py
    python3 -c '
import base64, zlib
source_code = """
import base64
def encode_payload(payload):
    key = b"s3cr3t_k3y"
    xored = bytes([b ^ key[i % len(key)] for i, b in enumerate(payload.encode())])
    return base64.b64encode(xored).decode()
"""
obfuscated = base64.b64encode(zlib.compress(source_code.encode())).decode()
with open("/home/user/encoder.py", "w") as f:
    f.write(f"import base64, zlib\nexec(zlib.decompress(base64.b64decode(b\"{obfuscated}\")))")
'

    # Create access.log
    cat << 'EOF' > /home/user/access.log
[2023-10-15 08:23:12] GET /index.php?payload=XhMBEgAAGkEABxIAR0IBAQcOEA0XExU= HTTP/1.1
[2023-10-15 09:01:45] GET /login.php?payload=RBEIHBcbQxMUEQAADwA= HTTP/1.1
[2023-10-15 10:15:30] GET /search.php?payload=AAMBBQ1KCRZGAwAKAEISAAANFAYDEhkfGw== HTTP/1.1
[2023-10-15 11:42:05] GET /profile.php?payload=XhMBEgAAGkEIDBYAAkIdBxMSRkIEAAARDA== HTTP/1.1
EOF

    chmod -R 777 /home/user
