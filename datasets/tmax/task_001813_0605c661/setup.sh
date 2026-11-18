#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

base_dir = "/home/user/artifacts"
os.makedirs(os.path.join(base_dir, "archive_A"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "archive_B", "nested"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "safe_zone"), exist_ok=True)

loop_link_1 = os.path.join(base_dir, "archive_A", "link_to_B")
loop_link_2 = os.path.join(base_dir, "archive_B", "nested", "link_to_A")

if not os.path.exists(loop_link_1):
    os.symlink(os.path.join(base_dir, "archive_B"), loop_link_1)
if not os.path.exists(loop_link_2):
    os.symlink(os.path.join(base_dir, "archive_A"), loop_link_2)

files = [
    ("archive_A/artifact1.blob", 150000, "aa" * 32),
    ("archive_A/small.blob", 50000, "bb" * 32),
    ("archive_B/nested/artifact2.blob", 120000, "cc" * 32),
    ("safe_zone/ignore.txt", 200000, "dd" * 32),
    ("safe_zone/artifact3.blob", 100001, "ee" * 32),
]

for rel_path, size, hex_data in files:
    full_path = os.path.join(base_dir, rel_path)
    with open(full_path, "wb") as f:
        f.write(bytes.fromhex(hex_data))
        f.write(b"\x00" * (size - 32))
'

    chmod -R 777 /home/user
