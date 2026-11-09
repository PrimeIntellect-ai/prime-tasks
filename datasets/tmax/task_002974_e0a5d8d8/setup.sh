#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_audits.txt
VXNlciBhZG1pbiBsb2dnZWQgaW4=
RmlsZSAvZXRjL3Bhc3N3ZCBhY2Nlc3NlZA==
RmFpbGVkIHN1IGF0dGVtcHQgYnkgdXNlciBqb2U=
EOF

    chmod -R 777 /home/user
