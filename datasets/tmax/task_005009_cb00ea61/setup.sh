#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip systemd dbus
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.config/systemd/user/
    mkdir -p /home/user/scripts
    mkdir -p /home/user/storage
    mkdir -p /home/user/logs

    touch /home/user/storage/base-image.qcow2

    cat << 'EOF' > /home/user/.config/systemd/user/prepare-disk.service
[Unit]
Description=Prepare VM Disk Directory Structure

[Service]
Type=oneshot
ExecStart=/bin/ln -sf /home/user/storage/base-image.qcow2 /home/user/active-disk.qcow2
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/vm-launcher.service
[Unit]
Description=Launch Python QEMU VM Controller

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /home/user/scripts/launch_vm.py
EOF

    cat << 'EOF' > /home/user/scripts/launch_vm.py
#!/usr/bin/env python3
import os
import sys

disk_path = "/home/user/active-disk.qcow2"
log_path = "/home/user/vm_run.log"

if not os.path.exists(disk_path):
    print(f"Error: Disk not found at {disk_path}!", file=sys.stderr)
    sys.exit(1)

with open(log_path, "a") as f:
    f.write("SUCCESS\n")

print("VM Launched successfully.")
EOF
    chmod +x /home/user/scripts/launch_vm.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
