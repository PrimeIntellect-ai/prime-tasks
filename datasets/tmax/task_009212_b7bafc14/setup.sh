#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.json
[
  {"tx_id": "T1", "waits_for": "T2"},
  {"tx_id": "T2", "waits_for": "T3"},
  {"tx_id": "T3", "waits_for": "T1"},
  {"tx_id": "T3", "waits_for": "T4"},
  {"tx_id": "T4", "waits_for": "T5"},
  {"tx_id": "T5", "waits_for": "T6"},
  {"tx_id": "T6", "waits_for": "T4"},
  {"tx_id": "T6", "waits_for": "T7"},
  {"tx_id": "T7", "waits_for": "T8"},
  {"tx_id": "T8", "waits_for": "T9"},
  {"tx_id": "T9", "waits_for": "T7"},
  {"tx_id": "T2", "waits_for": "T9"},
  {"tx_id": "T10", "waits_for": "T11"},
  {"tx_id": "T11", "waits_for": "T10"},
  {"tx_id": "T11", "waits_for": "T1"},
  {"tx_id": "T11", "waits_for": "T2"},
  {"tx_id": "T12", "waits_for": "T13"},
  {"tx_id": "T13", "waits_for": "T14"}
]
EOF

    chmod -R 777 /home/user
