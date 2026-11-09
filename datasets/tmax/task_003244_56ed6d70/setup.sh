#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_data

    cat << 'EOF' > /home/user/audit_data/transfers.jsonl
{"tx_id": "t01", "source": "NODE_SUSPECT", "target": "NODE_A", "bytes": 500, "status": "COMPLETED"}
{"tx_id": "t02", "source": "NODE_A", "target": "NODE_B", "bytes": 200, "status": "COMPLETED"}
{"tx_id": "t03", "source": "NODE_B", "target": "NODE_VAULT", "bytes": 100, "status": "COMPLETED"}
{"tx_id": "t04", "source": "NODE_SUSPECT", "target": "NODE_C", "bytes": 8000, "status": "FAILED"}
{"tx_id": "t05", "source": "NODE_C", "target": "NODE_VAULT", "bytes": 100, "status": "COMPLETED"}
{"tx_id": "t06", "source": "NODE_X", "target": "NODE_Y", "bytes": 15000, "status": "COMPLETED"}
{"tx_id": "t07", "source": "NODE_X", "target": "NODE_Z", "bytes": 12000, "status": "COMPLETED"}
{"tx_id": "t08", "source": "NODE_Z", "target": "NODE_W", "bytes": 1000, "status": "COMPLETED"}
{"tx_id": "t09", "source": "NODE_SUSPECT", "target": "NODE_D", "bytes": 300, "status": "COMPLETED"}
{"tx_id": "t10", "source": "NODE_D", "target": "NODE_E", "bytes": 300, "status": "COMPLETED"}
{"tx_id": "t11", "source": "NODE_E", "target": "NODE_F", "bytes": 300, "status": "COMPLETED"}
{"tx_id": "t12", "source": "NODE_F", "target": "NODE_VAULT", "bytes": 300, "status": "COMPLETED"}
EOF

    chown -R user:user /home/user/audit_data
    chmod -R 777 /home/user
