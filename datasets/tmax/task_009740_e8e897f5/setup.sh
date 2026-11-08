#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/archives

    # Create dummy binary files
    head -c 1024 /dev/urandom > /home/user/archives/data_A.bin
    head -c 1024 /dev/urandom > /home/user/archives/data_B.bin
    head -c 1024 /dev/urandom > /home/user/archives/data_C.bin
    head -c 1024 /dev/urandom > /home/user/archives/data_D.bin

    # Append correct signature to A and C
    echo -n "VALID_ARCHIVE_EOF" >> /home/user/archives/data_A.bin
    echo -n "VALID_ARCHIVE_EOF" >> /home/user/archives/data_C.bin

    # Append incorrect signature to B and D
    echo -n "INVALID_ARCHV_EOF" >> /home/user/archives/data_B.bin
    echo -n "VALID_ARCHIVE_ERR" >> /home/user/archives/data_D.bin

    # Create the TOML config file
    cat << 'EOF' > /home/user/project_files.toml
[archives]
files = [
    "/home/user/archives/data_A.bin",
    "/home/user/archives/data_B.bin",
    "/home/user/archives/data_C.bin",
    "/home/user/archives/data_D.bin"
]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/archives /home/user/project_files.toml
    chmod -R 777 /home/user
