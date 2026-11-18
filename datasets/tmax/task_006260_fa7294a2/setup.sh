#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build_setup/artifacts/libA
    mkdir -p /home/user/build_setup/artifacts/libB
    mkdir -p /home/user/build_setup/artifacts/libC
    mkdir -p /home/user/build_setup/artifacts/libD
    mkdir -p /home/user/build_setup/artifacts/libE

    cat << 'EOF' | gzip > /home/user/build_setup/artifacts/libA/build.log.gz
[2023-10-24 10:00:00] INFO: Starting build
[2023-10-24 10:00:05] INFO: Validating checksums
[2023-10-24 10:00:10] INFO: Build successful
EOF

    cat << 'EOF' | gzip > /home/user/build_setup/artifacts/libB/build.log.gz
[2023-10-24 10:10:00] INFO: Starting build
[2023-10-24 10:10:05] FATAL_ERROR: Pipeline failed
  Context: Validation phase
  Reason: Checksum mismatch
  File: binary_data.bin
[2023-10-24 10:10:06] INFO: Cleanup executed
EOF

    cat << 'EOF' | gzip > /home/user/build_setup/artifacts/libC/build.log.gz
[2023-10-24 10:20:00] INFO: Starting build
[2023-10-24 10:20:02] INFO: Warning
  Reason: Checksum mismatch in optional dependency
[2023-10-24 10:20:05] FATAL_ERROR: Disk full
  Context: Writing output
[2023-10-24 10:20:06] INFO: Aborting
EOF

    cat << 'EOF' | gzip > /home/user/build_setup/artifacts/libD/build.log.gz
[2023-10-24 10:30:00] INFO: Starting build
[2023-10-24 10:30:10] FATAL_ERROR: Integrity check failed
  Module: Core
  Action: Download
  Reason: Checksum mismatch
[2023-10-24 10:30:11] ERROR: System halted
EOF

    cat << 'EOF' | gzip > /home/user/build_setup/artifacts/libE/build.log.gz
[2023-10-24 10:40:00] INFO: Starting build
[2023-10-24 10:40:05] FATAL_ERROR: Network timeout
  Reason: Unreachable host
EOF

    cd /home/user/build_setup
    tar -czf /home/user/artifact_repo.tar.gz artifacts/
    cd /home/user
    rm -rf build_setup

    chmod -R 777 /home/user
