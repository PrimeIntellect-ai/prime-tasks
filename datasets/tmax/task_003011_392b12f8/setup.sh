#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Setup vendored package
    mkdir -p /app/vendored/qemu-net-builder/qemu_net_builder
    cat << 'EOF' > /app/vendored/qemu-net-builder/setup.py
from setuptools import setup, find_packages
setup(
    name="qemu-net-builder",
    version="0.1.0",
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'qemu-net-builder=qemu_net_builder.cli:main',
        ],
    },
)
EOF
    cat << 'EOF' > /app/vendored/qemu-net-builder/qemu_net_builder/__init__.py
EOF
    cat << 'EOF' > /app/vendored/qemu-net-builder/qemu_net_builder/utils.py
def get_subnet():
    # Deliberate bug
    return "192.168.100." + 0
EOF
    cat << 'EOF' > /app/vendored/qemu-net-builder/qemu_net_builder/cli.py
from .utils import get_subnet
def main():
    print(f"Network Builder starting on {get_subnet()}")
EOF

    # Setup filesystem structures for path traversal checks
    mkdir -p /home/user/vm_storage/safe_folder
    mkdir -p /home/user/vm_storage/symlink_folder
    mkdir -p /home/user/secret_host_data

    # Create symlinks
    ln -s /home/user/secret_host_data /home/user/vm_storage/symlink_folder/escape

    # Setup corpora
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Clean 1: standard
    cat << 'EOF' > /home/user/corpora/clean/c1.json
{"vm_name": "c1", "host_mount": "safe_folder"}
EOF

    # Clean 2: current dir
    cat << 'EOF' > /home/user/corpora/clean/c2.json
{"vm_name": "c2", "host_mount": "."}
EOF

    # Evil 1: direct traversal
    cat << 'EOF' > /home/user/corpora/evil/e1.json
{"vm_name": "e1", "host_mount": "../secret_host_data"}
EOF

    # Evil 2: symlink escape
    cat << 'EOF' > /home/user/corpora/evil/e2.json
{"vm_name": "e2", "host_mount": "symlink_folder/escape"}
EOF

    chown -R user:user /app/vendored /home/user
    chmod -R 777 /home/user
