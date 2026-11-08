#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential zlib1g-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zlib
import struct
import hashlib

def create_cbnd(path, files):
    magic = b"CBND"
    num_entries = len(files)

    header = magic + struct.pack("<I", num_entries)

    index_data = b""
    data_section = b""

    # Calculate initial offset for data section
    # Header (8) + (Index Entry Size (76) * num_entries)
    current_offset = 8 + (76 * num_entries)

    for filename, content in files:
        compressed_content = zlib.compress(content)
        comp_size = len(compressed_content)
        uncomp_size = len(content)

        # 64 bytes filename, null padded
        encoded_name = filename.encode('ascii')
        padded_name = encoded_name + b'\x00' * (64 - len(encoded_name))

        index_entry = padded_name + struct.pack("<III", comp_size, uncomp_size, current_offset)
        index_data += index_entry

        data_section += compressed_content
        current_offset += comp_size

    with open(path, "wb") as f:
        f.write(header)
        f.write(index_data)
        f.write(data_section)

# Setup directories
os.makedirs("/home/user/artifact_repo/core", exist_ok=True)
os.makedirs("/home/user/artifact_repo/plugins/net", exist_ok=True)

# Generate files
files_core = [
    ("kernel_module.bin", b"mock_kernel_data_123" * 100),
    ("init_sys.elf", b"ELF_mock_init_binary" * 50)
]

files_plugins = [
    ("tcp_handler.so", b"shared_object_tcp_stuff" * 80),
    ("udp_handler.so", b"shared_object_udp_stuff" * 80)
]

create_cbnd("/home/user/artifact_repo/core/base.cbnd", files_core)
create_cbnd("/home/user/artifact_repo/plugins/net/handlers.cbnd", files_plugins)

# Write a script to quickly compute expected manifest
manifest_lines = []
for bundle in [files_core, files_plugins]:
    for name, content in bundle:
        h = hashlib.sha256(content).hexdigest()
        manifest_lines.append(f"{h}  {name}\n")

manifest_lines.sort(key=lambda x: x.split("  ")[1])

with open("/tmp/expected_manifest.txt", "w") as f:
    f.writelines(manifest_lines)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
