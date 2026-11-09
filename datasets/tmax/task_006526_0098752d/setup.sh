#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/catalog.json
{
  "worker": ["v0.9.0", "v1.0.0", "v1.1.2", "v1.5.0", "v2.0.0"],
  "api": ["v1.0.0", "v1.0.1", "v1.2.0"]
}
EOF

    chmod -R 777 /home/user
