#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/access.log
GET /api/v1/status HTTP/1.1
Host: internal.corp
X-Action: Ignore
Cookie: auth_session=eyJ1c2VyIjogImFkbWluIiwgInNlY3JldCI6ICJ3cm9uZ19rZXkifQ==

GET /api/v1/data HTTP/1.1
Host: internal.corp
X-Action: Rotate-Target
Cookie: auth_session=eyJ1c2VyIjogImFkbWluIiwgInNlY3JldCI6ICJzdXBlcl9zZWNyZXRfb2xkX2tleV8xMjMifQ==

GET /api/v1/config HTTP/1.1
Host: internal.corp
X-Action: Skip
Cookie: auth_session=eyJ1c2VyIjogImd1ZXN0IiwgInNlY3JldCI6ICJub25lIn0=
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
