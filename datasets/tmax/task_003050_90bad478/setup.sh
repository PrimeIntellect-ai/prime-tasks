#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make gcc
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/log-archiver-lib-1.2.0/log_archiver
    mkdir -p /app/oracle

    # Create Makefile with deliberate perturbation
    cat << 'EOF' > /app/vendored/log-archiver-lib-1.2.0/Makefile
all:
	@echo "Building..."
test:
	export LOCK_DIR=/usr/bin/locked
	@echo "Running tests..."
install:
	@echo "Installing..."
EOF

    # Create flock_manager.py with deliberate perturbation
    cat << 'EOF' > /app/vendored/log-archiver-lib-1.2.0/log_archiver/flock_manager.py
import fcntl

class FlockManager:
    def lock(self, fd):
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
EOF

    # Create a dummy oracle binary
    cat << 'EOF' > /app/oracle/dedup_oracle.bin
#!/usr/bin/env python3
import sys
print("Oracle executed")
EOF
    chmod +x /app/oracle/dedup_oracle.bin

    # Create user and home directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/backup_repo/objects

    # Set permissions
    chmod -R 777 /home/user
