#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest cryptography bandit

useradd -m -s /bin/bash user || true

python3 -c "
import base64
import os
from cryptography.fernet import Fernet

key = Fernet.generate_key()
with open('/home/user/fernet.key', 'wb') as f:
    f.write(key)
"

cat << 'EOF' > /home/user/raw_audit.log
2023-10-01 12:00:00 - User admin logged in.
2023-10-01 12:05:13 - Payment processed for CC: 1234567812345678, amount: $150.00.
2023-10-01 12:10:02 - Failed transaction for card 9876543210987654 due to NSF.
2023-10-01 12:15:00 - User admin logged out.
EOF

chmod -R 777 /home/user
