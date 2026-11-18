#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build_env
    cd /home/user/build_env

    cat << 'EOF' > migrate_and_merge.py
import json
import sys

def process(file1, file2, outfile):
    with open(file1, 'r') as f:
        l1 = json.load(f)
    with open(file2, 'r') as f:
        l2 = json.load(f)

    merged = l1 + l2
    migrated = []

    for item in merged:
        migrated.append({
            "id": item["id"],
            "timestamp": item["upload_time"],
            "size_kb": item["size_bytes"] // 1024,
            "schema_version": 2
        })

    migrated.sort(key=lambda x: (x["timestamp"], x["id"]))

    with open(outfile, 'w') as f:
        json.dump(migrated, f, indent=2)

if __name__ == "__main__":
    process(sys.argv[1], sys.argv[2], sys.argv[3])
EOF

    cat << 'EOF' > list1.json
[
  {"id": "pkg-alpha", "upload_time": 1670000100, "size_bytes": 2048},
  {"id": "pkg-delta", "upload_time": 1670000050, "size_bytes": 10240},
  {"id": "pkg-gamma", "upload_time": 1670000100, "size_bytes": 4096}
]
EOF

    cat << 'EOF' > list2.json
[
  {"id": "pkg-beta", "upload_time": 1670000075, "size_bytes": 5120},
  {"id": "pkg-epsilon", "upload_time": 1670000050, "size_bytes": 1024}
]
EOF

    chown -R user:user /home/user/build_env
    chmod -R 777 /home/user
