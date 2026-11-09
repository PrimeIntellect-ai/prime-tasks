#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/backups

    python3 -c '
import os
import struct

os.makedirs("/home/user/backups", exist_ok=True)

chunks = [
    (0, b"Part 1 of the secret backup data. "),
    (1, b"Part 2 contains crucial info. "),
    (2, b"Part 3 is the end of the data archive.")
]

file_mapping = {
    0: "chunk_X.dat",
    1: "chunk_A.dat",
    2: "chunk_Z.dat"
}

magic = b"ARCHIVE_BKP"

for seq_id, payload in chunks:
    filename = f"/home/user/backups/{file_mapping[seq_id]}"
    with open(filename, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<B", seq_id))
        f.write(struct.pack("<I", len(payload)))
        f.write(payload)
        f.write(b"GARBAGE_DATA_THAT_SHOULD_BE_IGNORED")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
