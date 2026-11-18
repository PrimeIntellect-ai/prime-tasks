#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_task.py
import os
import h5py

def setup_task():
    target_seq = "ACGTACGTACGATCAGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACG"
    primer_seq = "GATCA"

    file_path = "/home/user/assay_data.h5"
    with h5py.File(file_path, "w") as f:
        f.create_dataset("target", data=target_seq.encode("ascii"))
        f.create_dataset("primer", data=primer_seq.encode("ascii"))

    os.chmod(file_path, 0o644)

if __name__ == "__main__":
    setup_task()
EOF

    python3 /tmp/setup_task.py
    rm /tmp/setup_task.py

    chmod -R 777 /home/user
