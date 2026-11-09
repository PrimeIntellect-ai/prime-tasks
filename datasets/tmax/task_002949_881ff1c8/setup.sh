#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar libc-bin
    pip3 install pytest

    mkdir -p /home/user/artifacts
    cd /home/user/artifacts

    # Create dummy archives
    tar -czf bin_A192.tar.gz -T /dev/null
    tar -czf bin_B834.tar.gz -T /dev/null
    tar -czf bin_C771.tar.gz -T /dev/null

    # Create the plain text manifest
    cat << 'EOF' > manifest_plain.txt
[Artifact]
Temp-Name: bin_A192.tar.gz
Real-Name: auth-service-1.0.tar.gz
Timestamp: 2023-10-01T10:00:00Z

[Artifact]
Temp-Name: bin_B834.tar.gz
Real-Name: payment-gateway-2.1.tar.gz
Timestamp: 2023-10-01T10:05:00Z

[Artifact]
Temp-Name: bin_C771.tar.gz
Real-Name: ui-components-3.4.tar.gz
Timestamp: 2023-10-01T10:10:00Z
EOF

    # Convert to UTF-16LE
    iconv -f UTF-8 -t UTF-16LE manifest_plain.txt > incoming_manifest.log
    rm manifest_plain.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
