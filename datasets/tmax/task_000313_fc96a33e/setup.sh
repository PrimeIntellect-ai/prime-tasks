#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

os.makedirs("/home/user/storage/docs", exist_ok=True)
os.makedirs("/home/user/storage/images", exist_ok=True)

files_data = {
    "/home/user/storage/docs/report.txt": b"Quarterly report data: all systems nominal.",
    "/home/user/storage/docs/legacy_notes.txt": b"Old notes. Do not delete.",
    "/home/user/storage/images/photo.png": b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR",
}

for path, content in files_data.items():
    with open(path, "wb") as f:
        f.write(content)

try:
    os.symlink("/home/user/storage", "/home/user/storage/docs/loop")
except FileExistsError:
    pass

log_entries = [
    "=== RECORD ===",
    "Path: /home/user/storage/docs/report.txt",
    "Type: File",
    "Action: BackedUp",
    "=== END ===",
    "=== RECORD ===",
    "Path: /home/user/storage/docs/loop",
    "Type: Symlink",
    "Action: InfiniteLoopAborted",
    "=== END ===",
    "=== RECORD ===",
    "Path: /home/user/storage/docs/legacy_notes.txt",
    "Type: File",
    "Action: BackedUp",
    "=== END ===",
    "=== RECORD ===",
    "Path: /home/user/storage/images/photo.png",
    "Type: File",
    "Action: BackedUp",
    "=== END ===",
    "=== RECORD ===",
    "Path: /home/user/storage/images/temp_cache.tmp",
    "Type: File",
    "Action: Skipped",
    "=== END ==="
]

log_content = "\n".join(log_entries) + "\n"
with open("/home/user/storage_audit.log", "w", encoding="utf-16le") as f:
    f.write(log_content)
'

    chmod -R 777 /home/user
