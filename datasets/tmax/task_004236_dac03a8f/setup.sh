#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct

os.makedirs('/home/user/legacy_docs', exist_ok=True)

def create_asset(filename, asset_type, payload):
    magic = b'DOCS'
    type_bytes = struct.pack('>I', asset_type)
    timestamp = struct.pack('>Q', 1672531200) # Arbitrary timestamp

    with open(f'/home/user/legacy_docs/{filename}', 'wb') as f:
        f.write(magic + type_bytes + timestamp + payload)

# File 1: Text Document (Type 1)
payload1 = b"""Welcome to [COMPANY_NAME]!
DRAFT: This is a note to the editor.
We are excited to have you. [COMPANY_NAME] values its employees.
DRAFT: Fix the punctuation here.
End of document."""
create_asset('intro.asset', 1, payload1)

# File 2: Image (Type 2)
payload2 = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR...'
create_asset('logo.asset', 2, payload2)

# File 3: Text Document (Type 1)
payload3 = b"""DRAFT: To be deleted.
The [COMPANY_NAME] quarterly report.
Revenue is up by 15% at [COMPANY_NAME]."""
create_asset('report.asset', 1, payload3)

# File 4: Text Document (Type 1)
payload4 = b"""Just a normal file.
No drafts here.
Only [COMPANY_NAME] everywhere."""
create_asset('normal.asset', 1, payload4)

# File 5: Image (Type 2)
payload5 = b'\xff\xd8\xff\xe0\x00\x10JFIF...'
create_asset('diagram.asset', 2, payload5)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
