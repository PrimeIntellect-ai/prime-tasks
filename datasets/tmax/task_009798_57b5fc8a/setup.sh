#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs("/home/user/quarantine", exist_ok=True)

records = [
    {
        "ArchiveID": "arch_001_safe",
        "ExtractedTo": "/opt/app/data/file1.txt",
        "Status": "SUCCESS",
        "Bytes": b"\x50\x4B\x03\x04" + b"\x00" * 12
    },
    {
        "ArchiveID": "arch_002_slip",
        "ExtractedTo": "/opt/app/data/../../../etc/shadow",
        "Status": "QUARANTINED",
        "Bytes": b"\x50\x4B\x07\x08\xDE\xAD\xBE\xEF\x01\x02\x03\x04\x05\x06\x07\x08"
    },
    {
        "ArchiveID": "arch_003_fail",
        "ExtractedTo": "/opt/app/data/../../root/secret",
        "Status": "FAILED",
        "Bytes": b"\x00" * 16
    },
    {
        "ArchiveID": "arch_004_slip",
        "ExtractedTo": "C:\\temp\\..\\..\\Windows\\System32\\cmd.exe",
        "Status": "QUARANTINED",
        "Bytes": b"\x1F\x8B\x08\x00\x00\x00\x00\x00\x02\x03\xAA\xBB\xCC\xDD\xEE\xFF"
    },
    {
        "ArchiveID": "arch_005_safe",
        "ExtractedTo": "/opt/app/data/safe_dir/file.txt",
        "Status": "QUARANTINED",
        "Bytes": b"\x11" * 16
    }
]

log_content = ""
for r in records:
    log_content += "BEGIN_RECORD\n"
    log_content += "Timestamp: 2023-10-27T10:00:00Z\n"
    log_content += f"ArchiveID: {r['ArchiveID']}\n"
    log_content += f"ExtractedTo: {r['ExtractedTo']}\n"
    log_content += f"Status: {r['Status']}\n"
    log_content += "END_RECORD\n"

with open("/home/user/extraction_logs.dat", "w", encoding="utf-16le") as f:
    f.write(log_content)

for r in records:
    with open(f"/home/user/quarantine/{r['ArchiveID']}.bin", "wb") as f:
        f.write(r['Bytes'])
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
