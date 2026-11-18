#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deps.json
{
  "libMain": {"deps": ["libMath", "libIO", "libMatrix"], "weight": 10},
  "libMatrix": {"deps": ["libMath", "libVector"], "weight": 50},
  "libVector": {"deps": ["libMath"], "weight": 20},
  "libIO": {"deps": ["libCore"], "weight": 5},
  "libMath": {"deps": ["libCore"], "weight": 100},
  "libCore": {"deps": [], "weight": 1}
}
EOF

    chmod -R 777 /home/user
