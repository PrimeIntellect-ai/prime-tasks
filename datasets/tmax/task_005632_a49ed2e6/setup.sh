#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_changes.jsonl
{"id": "evt_05", "ts": 1700000045, "module": "ui", "key": "greeting", "value": "Hello \uD83C\uDF0D"}
{"id": "evt_02", "ts": 1700000010, "module": "db", "key": "timeout", "value": "30"}
{"id": "evt_01", "ts": 1700000000, "module": "ui", "key": "greeting", "value": "Hello"}
{"id": "evt_08", "ts": 1700000110, "module": "ui", "key": "greeting", "value": "Hello \uD83C\uDF0D"}
{"id": "evt_04", "ts": 1700000030, "module": "auth", "key": "method", "value": "oauth2"}
{"id": "evt_03", "ts": 1700000010, "module": "db", "key": "timeout", "value": "30"}
{"id": "evt_07", "ts": 1700000080, "module": "auth", "key": "method", "value": "saml"}
{"id": "evt_06", "ts": 1700000045, "module": "ui", "key": "greeting", "value": "Hello \uD83C\uDF0D"}
{"id": "evt_09", "ts": 1700000115, "module": "db", "key": "timeout", "value": "60"}
{"id": "evt_10", "ts": 1700000120, "module": "db", "key": "timeout", "value": "60"}
EOF

    chmod -R 777 /home/user
