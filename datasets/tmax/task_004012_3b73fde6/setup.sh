#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/storage
    cd /home/user/storage

    cat << 'EOF' > generate_data.py
import tarfile
import struct
import json
import io
import os

with tarfile.open("/home/user/storage/telemetry_dump.tar.gz", "w:gz") as tar:
    for i in range(1, 101):
        # 1. Generate Log
        log_content = f"timestamp,hostname,error_code,message\n"
        error_code = 505 if i % 7 == 0 else 200
        log_content += f"2023-10-25T10:00:00Z,srv-{i},{error_code},status update\n"

        log_bytes = log_content.encode('utf-8')
        tinfo = tarfile.TarInfo(f"log_{i:03d}.log")
        tinfo.size = len(log_bytes)
        tar.addfile(tinfo, io.BytesIO(log_bytes))

        # 2. Generate Meta
        version = 1.0 if i % 11 == 0 else 2.5
        meta_id = f"META-{i:03d}"
        meta_content = json.dumps({"id": meta_id, "version": version, "size": 1024})

        meta_bytes = meta_content.encode('utf-8')
        tinfo = tarfile.TarInfo(f"meta_{i:03d}.meta")
        tinfo.size = len(meta_bytes)
        tar.addfile(tinfo, io.BytesIO(meta_bytes))

        # 3. Generate Bin
        # Magic: big endian, Version: little endian
        magic = 0xDEADC0DE if i % 5 == 0 else 0xCAFEBABE
        b_version = 3 if i % 2 == 0 else 1

        bin_bytes = struct.pack(">I", magic) + struct.pack("<I", b_version) + b"payload_data"
        tinfo = tarfile.TarInfo(f"state_{i:03d}.bin")
        tinfo.size = len(bin_bytes)
        tar.addfile(tinfo, io.BytesIO(bin_bytes))
EOF

    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
