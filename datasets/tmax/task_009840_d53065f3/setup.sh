#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go coreutils gawk
    pip3 install pytest

    mkdir -p /home/user/intercepted

    # Create payload 1
    echo -n "malicious_payload_alpha_v1.0" > /home/user/intercepted/payload_01.dat
    sha256sum /home/user/intercepted/payload_01.dat | gawk '{print $1}' > /home/user/threat_intel.db

    # Create payload 3
    echo -n "malicious_payload_beta_v2.0" > /home/user/intercepted/payload_03.dat
    sha256sum /home/user/intercepted/payload_03.dat | gawk '{print $1}' >> /home/user/threat_intel.db

    # Create payload 2 (XOR encrypted)
    python3 -c "
import sys
plaintext = b'INITIAL_BUFFER_OVERFLOW_SEQUENCE_SECRET_ACCESS_TOKEN=X9f2M4pL1vQ8z_ENDING_SEQUENCE'
ciphertext = bytes([b ^ 0x7A for b in plaintext])
with open('/home/user/intercepted/payload_02.dat', 'wb') as f:
    f.write(ciphertext)
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
