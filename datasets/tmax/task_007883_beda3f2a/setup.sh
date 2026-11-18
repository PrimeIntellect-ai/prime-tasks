#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident/evidence
    chmod 777 /home/user/incident/evidence

    cat << 'EOF' > /home/user/incident/evidence/requests.log
192.168.1.10|aG9tZSUyMHBhZ2U=
10.0.0.5|JTNDc3ZnJTIwb25sb2FkJTNEYWxlcnQlMjgxJTI5JTNF
172.16.0.2|U0VMRUNUJTIwJTI0JTIwRlJPTSUyMHVzZXJz
192.168.1.11|Y29udGFjdCUyMHVz
EOF

    echo "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval';" > /home/user/incident/csp_policy.txt

    chmod -R 777 /home/user
