#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_index.json
{
  "packages": {
    "lib-alpha": { "v": "1.0", "deps": ["lib-beta", "lib-gamma"] },
    "lib-beta": { "v": "2.2", "deps": ["lib-delta"] },
    "lib-gamma": { "v": "1.1", "deps": [] },
    "lib-delta": { "v": "3.0", "deps": ["lib-gamma"] },
    "lib-core": { "v": "0.9", "deps": ["lib-alpha", "lib-epsilon"] },
    "lib-epsilon": { "v": "4.1", "deps": [] }
  }
}
EOF

    chmod -R 777 /home/user
