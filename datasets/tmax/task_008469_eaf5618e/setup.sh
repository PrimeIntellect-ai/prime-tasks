#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_data.json
[
  {"full_name": "Alice Walker", "birth_year": "1990", "id": "1"},
  {"full_name": "Bob Martin Lee", "birth_year": "1985", "id": "2"}
]
EOF

    chmod -R 777 /home/user
