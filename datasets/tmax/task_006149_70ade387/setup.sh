#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user

    # Create the test payload binary using python to avoid echo -e issues
    python3 -c "
with open('/home/user/test_payload.bin', 'wb') as f:
    f.write(b'\x01\x14\x03\x02\x05\x03\x02\xFB\x03\x04')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
