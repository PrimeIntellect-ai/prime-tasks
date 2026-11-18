#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup_vault/dir_A
    mkdir -p /home/user/backup_vault/dir_B/sub_C

    cat << 'EOF' > /home/user/backup_catalog.json
[
  {"file_id": "bkp-101", "owner": "alice_admin", "timestamp": "2023-01-01"},
  {"file_id": "bkp-102", "owner": "bob_user", "timestamp": "2023-01-02"},
  {"file_id": "bkp-103", "owner": "alice_admin", "timestamp": "2023-01-03"},
  {"file_id": "bkp-104", "owner": "alice_admin", "timestamp": "2023-01-04"}
]
EOF

    python3 -c '
import os
def write_file(path, data):
    with open(path, "wb") as f:
        f.write(data)

write_file("/home/user/backup_vault/dir_A/bkp-101", b"\x1f\x8b\x08\x00\x00\x00\x00\x00dummy data\n")
write_file("/home/user/backup_vault/dir_B/bkp-102", b"\x1f\x8b\x08\x00\x00\x00\x00\x00")
write_file("/home/user/backup_vault/dir_B/sub_C/bkp-103", b"\x50\x4b\x03\x04\x00\x00\x00\x00")
write_file("/home/user/backup_vault/dir_B/sub_C/bkp-104", b"\x1f\x8b\x08\x00\x00\x00\x00\x00more data\n")
'

    chown -R user:user /home/user/backup_vault /home/user/backup_catalog.json
    chmod -R 777 /home/user
