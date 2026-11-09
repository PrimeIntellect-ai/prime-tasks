#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/dataset/raw/dirA/dirB
    mkdir -p /home/user/dataset/raw/dirC/dirD

    python3 -c '
import struct
import os

base = "/home/user/dataset/raw"

# Create 50 bin files and 50 tsv files with predictable means
for i in range(100):
    val = float(i)
    # 10 identical values so the mean is exactly `val`
    values = [val] * 10

    if i % 2 == 0:
        # write .bin in dirA/dirB
        path = os.path.join(base, f"dirA/dirB/file_{i}.bin")
        with open(path, "wb") as f:
            f.write(struct.pack("<10d", *values))
    else:
        # write .tsv in dirC/dirD
        path = os.path.join(base, f"dirC/dirD/file_{i}.tsv")
        with open(path, "w") as f:
            f.write("\t".join(f"{v:.4f}" for v in values))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
