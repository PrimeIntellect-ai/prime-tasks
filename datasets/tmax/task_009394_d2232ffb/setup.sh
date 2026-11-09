#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/requests.log
GET /api/v1/event?data=eyJ1c2VySWQiOiAxMDEsICJhY3Rpb24iOiAibG9naW4ifQ== HTTP/1.1
GET /api/v1/other?data=eyJ1c2VySWQiOiA5OTksICJhY3Rpb24iOiAiYmFkIn0= HTTP/1.1
POST /api/v1/event?data=eyJ1c2VySWQiOiAyMDQsICJhY3Rpb24iOiAicHVyY2hhc2UifQ== HTTP/1.1
GET /api/v1/event?data=eyJ1c2VySWQiOiAyMDQsICJhY3Rpb24iOiAicHVyY2hhc2UifQ== HTTP/1.1
GET /api/v2/event?data=eyJ1c2VySWQiOiA5OSwgImFjdGlvbiI6ICJsb2dvdXQifQ== HTTP/1.1
GET /api/v1/event?data=eyJ1c2VySWQiOiA5OSwgImFjdGlvbiI6ICJsb2dvdXQifQ== HTTP/1.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
