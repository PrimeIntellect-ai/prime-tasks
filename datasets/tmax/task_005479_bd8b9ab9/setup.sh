#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # Create mock disk image with deleted log string
    head -c 1024 /dev/urandom > disk.img
    echo -n "[DELETED_LOG] TX_ID: f8a92b1c" >> disk.img
    head -c 1024 /dev/urandom >> disk.img

    # Create memory dump with the target transaction
    head -c 2048 /dev/urandom > mem.dmp
    echo -n "TX_START|f8a92b1c|PAYMENT_DATA_REQ_77491_SUCCESS|TX_END" >> mem.dmp
    head -c 1024 /dev/urandom >> mem.dmp

    # Create the buggy Python script
    cat << 'EOF' > recover_tx.py
import sys

def extract_payload(dmp_path, tx_id):
    with open(dmp_path, 'rb') as f:
        data = f.read()

    marker = b"TX_START|" + tx_id.encode() + b"|"
    start_idx = data.find(marker)

    if start_idx == -1:
        print("Transaction ID not found in memory dump.")
        sys.exit(1)

    payload_start = start_idx + len(marker)
    end_idx = data.find(b"|TX_END", payload_start)

    if end_idx == -1:
        print("End marker not found.")
        sys.exit(1)

    # BUG: Off-by-one error truncating the last byte of the payload
    payload = data[payload_start : end_idx - 1]

    return payload.decode('utf-8')

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 recover_tx.py <dump_file> <tx_id>")
        sys.exit(1)

    dump_file = sys.argv[1]
    tx_id = sys.argv[2]

    recovered = extract_payload(dump_file, tx_id)
    print("Recovered Payload:", recovered)
EOF
    chmod +x recover_tx.py

    chmod -R 777 /home/user
