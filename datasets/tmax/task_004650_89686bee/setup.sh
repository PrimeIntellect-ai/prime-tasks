#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar
    pip3 install pytest

    mkdir -p /home/user/staging
    mkdir -p /home/user/release

    # Create the secret file and dummy data
    mkdir -p /tmp/artifact_build
    echo "ARTIFACT_VERIFIED_77392" > /tmp/artifact_build/secret_key.txt
    dd if=/dev/urandom of=/tmp/artifact_build/dummy_data.bin bs=1K count=100 2>/dev/null

    # Create the tar.gz archive
    cd /tmp/artifact_build
    tar -czf /tmp/assembled_original.tar.gz secret_key.txt dummy_data.bin

    # Split the archive into parts
    cd /home/user/staging
    split -b 40K /tmp/assembled_original.tar.gz chunk_part_

    # Rename parts to scramble them alphabetically
    mv chunk_part_aa chunk_B.bin
    mv chunk_part_ab chunk_C.bin
    mv chunk_part_ac chunk_A.bin

    # Create manifest.txt
    cat << 'EOF' > /home/user/staging/manifest.txt
# Artifact Manifest v1.0
# The chunks must be assembled in the following order:

CHUNK: chunk_B.bin
IGNORE_THIS: chunk_A.bin
CHUNK: chunk_C.bin
CHUNK: chunk_A.bin

# End of manifest
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
