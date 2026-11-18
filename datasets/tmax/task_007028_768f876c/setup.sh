#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential sqlite3 libsqlite3-dev pkg-config
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_org.jsonl
{"emp_id": "E1", "name": "Alice (CEO)", "manager_id": null, "salary": 250000}
{"emp_id": "E2", "name": "Bob (VP Tech)", "manager_id": "E1", "salary": 180000}
{"emp_id": "E3", "name": "Charlie (VP Sales)", "manager_id": "E1", "salary": 170000}
{"emp_id": "E4", "name": "Diana (Director)", "manager_id": "E2", "salary": 140000}
{"emp_id": "E5", "name": "Evan (Manager)", "manager_id": "E4", "salary": 110000}
{"emp_id": "E6", "name": "Fiona (Engineer)", "manager_id": "E5", "salary": 95000}
{"emp_id": "E7", "name": "George (Engineer)", "manager_id": "E5", "salary": 90000}
{"emp_id": "E8", "name": "Hannah (Sales Lead)", "manager_id": "E3", "salary": 120000}
{"emp_id": "E9", "name": "Ian (Sales Rep)", "manager_id": "E8", "salary": 75000}
{"emp_id": "E10", "name": "Julia (Sales Rep)", "manager_id": "E8", "salary": 80000}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
