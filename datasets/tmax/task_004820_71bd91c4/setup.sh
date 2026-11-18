#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/create_setup.py
import base64
import zlib

source_code = """
import sys

def process_ticket(ticket_id):
    if not ticket_id.startswith("TICKET_"):
        return False
    parts = ticket_id.split("_")
    if len(parts) == 2:
        pin = parts[1]
        if len(pin) == 4 and pin.isdigit():
            if (int(pin) * 7) % 9999 == 4321:
                raise AssertionError("CRITICAL_FAILURE: " + ticket_id)
    return True

if __name__ == "__main__":
    if len(sys.argv) > 1:
        process_ticket(sys.argv[1])
"""

compressed = zlib.compress(source_code.encode('utf-8'))
encoded = base64.b64encode(compressed).decode('utf-8')

with open('/home/user/ticket_processor.py', 'w') as f:
    f.write(f"import base64, zlib\nexec(zlib.decompress(base64.b64decode('{encoded}')).decode('utf-8'))\n")
EOF

    python3 /home/user/create_setup.py
    rm /home/user/create_setup.py

    chmod -R 777 /home/user
