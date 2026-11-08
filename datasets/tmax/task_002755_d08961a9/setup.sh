#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq imagemagick
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create policy image
    convert -background white -fill black -pointsize 24 label:"AUDIT POLICY:\nReject any transaction log that produces a cyclic dependency\nin ADMIN role delegations.\nTransactions with cycles are EVIL. Otherwise CLEAN." /app/policy.png

    # Clean corpus (No ADMIN cycles)
    cat << 'EOF' > /app/corpus/clean/log1.json
[
  {"action": "GRANT", "source": "U1", "target": "U2", "role": "ADMIN"},
  {"action": "GRANT", "source": "U2", "target": "U3", "role": "USER"},
  {"action": "GRANT", "source": "U3", "target": "U1", "role": "USER"}
]
EOF

    # Evil corpus (ADMIN cycle: U1 -> U2 -> U3 -> U1)
    cat << 'EOF' > /app/corpus/evil/log1.json
[
  {"action": "GRANT", "source": "U1", "target": "U2", "role": "ADMIN"},
  {"action": "GRANT", "source": "U2", "target": "U3", "role": "ADMIN"},
  {"action": "GRANT", "source": "U3", "target": "U1", "role": "ADMIN"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
