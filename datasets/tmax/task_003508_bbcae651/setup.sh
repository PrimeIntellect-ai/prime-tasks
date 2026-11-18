#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip acl gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/release_v2/api /home/user/release_v2/config /home/user/release_v2/static
    mkdir -p /home/user/production

    echo "print('api')" > /home/user/release_v2/api/server.py
    echo "db=localhost" > /home/user/release_v2/config/db.conf
    echo "body { color: red; }" > /home/user/release_v2/static/style.css

    cat << 'EOF' > /home/user/manifest.txt
api/server.py | 750 | www-data | r-x
config/db.conf | 600 | www-data | r--
static/style.css | 644 | daemon | r--
EOF

    chmod -R 777 /home/user
