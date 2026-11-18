#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_test_data.py
import struct

records = [
    (0x01, 0.0),      # START
    (0x02, 10.0),     # DATA (collected)
    (0x02, 20.0),     # DATA (collected)
    (0x03, 0.0),      # STOP
    (0x02, 100.0),    # DATA (ignored, IDLE)
    (0x01, 0.0),      # START
    (0x02, 30.0),     # DATA (collected)
    (0x03, 0.0),      # STOP
]

with open("/home/user/test_data.bin", "wb") as f:
    for cmd, val in records:
        f.write(struct.pack("<Bd", cmd, val))
EOF

    python3 /home/user/setup_test_data.py
    rm /home/user/setup_test_data.py

    chmod -R 777 /home/user
