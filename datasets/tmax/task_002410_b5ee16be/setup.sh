#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts

    # Copy some standard system binaries to act as our ELF artifacts
    cp /bin/true /home/user/artifacts/sys_true
    cp /bin/false /home/user/artifacts/sys_false
    cp /bin/ls /home/user/artifacts/sys_ls

    # Create the noisy artifact log
    cat << 'EOF' > /home/user/artifact_log.txt
DEBUG: System boot sequence initiated.
INFO: Found 3 new uploads in quarantine.
VALIDATE: sys_true
WARN: Could not read metadata for temp_file.bin
VALIDATE: sys_false
ERROR: Invalid checksum on sys_cat
DEBUG: cleanup routine triggered
EOF

    chown -R user:user /home/user/artifacts
    chown user:user /home/user/artifact_log.txt

    chmod -R 777 /home/user
