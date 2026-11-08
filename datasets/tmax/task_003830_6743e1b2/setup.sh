#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    # Create the memory dump with embedded strings
    printf '\x00\x01\x02\x03\x04\x05Some random binary data\x00\x00CRASH_TX_ID: TX-999\x00\x08\x09More binary\x00' > /home/user/app_memory.dmp

    # Create the corrupted transactions JSON
    cat << 'EOF' > /home/user/transactions.json
{
  "TX-001": {"next": "TX-002", "timestamp": "2023-10-01T10:00:00Z"},
  "TX-002": {"next": "TX-003", "timestamp": "2023-10-01T10:01:00Z"},
  "TX-003": {"next": null, "timestamp": "2023-10-01T10:02:00Z"},
  "TX-997": {"next": "TX-998", "timestamp": "2023-10-01T10:03:00Z"},
  "TX-998": {"next": "TX-999", "timestamp": "2023-10-01T10:04:00Z"},
  "TX-999": {"next": "TX-998", "timestamp": "2023-10-01T10:05:00Z"}
}
EOF

    # Create the buggy Python script
    cat << 'EOF' > /home/user/log_parser.py
import json

def resolve_chain(tx_id, transactions, timeline):
    if tx_id is None or tx_id not in transactions:
        return

    timeline.append(tx_id)
    next_tx = transactions[tx_id].get("next")

    # Bug: No circular reference check
    resolve_chain(next_tx, transactions, timeline)

def main():
    with open("/home/user/transactions.json", "r") as f:
        transactions = json.load(f)

    timeline = []
    # Process standard chain
    resolve_chain("TX-001", transactions, timeline)
    # Process corrupted chain
    resolve_chain("TX-997", transactions, timeline)

    with open("/home/user/reconstructed_timeline.log", "w") as f:
        f.write("\n".join(timeline))

if __name__ == "__main__":
    main()
EOF

    chmod 644 /home/user/app_memory.dmp
    chmod 644 /home/user/transactions.json
    chmod 755 /home/user/log_parser.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
