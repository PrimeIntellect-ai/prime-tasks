#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/headers.log
GET /admin/dashboard HTTP/1.1
Host: internal-app.local
Cookie: auth_session=eyJ1c2VyIjogImFkbWluIiwgInRva2VuX2hhc2giOiAiY2RjZTZlOWIyZTBiOWFmNzNiMTgzNmZkZWY4NzE3YjZhZjg2NTVjOTdkMzBhMjFkYTYxZWIzMjhhZDU2NjYxZSIsICJwcm9maWxlX3BpYyI6ICJqYXZhc2NyaXB0OmFsZXJ0KCdYU1MnKSIsICJyb2xlIjogImFkbWluIn0=
User-Agent: curl/7.81.0
Accept: */*
EOF

    chmod -R 777 /home/user
