#!/bin/bash
mkdir -p /logs/verifier

WORKDIR=""
CONFIG_BACKUP=""
cleanup_verifier() {
    if [ -n "$CONFIG_BACKUP" ] && [ -f "$CONFIG_BACKUP" ]; then
        cp "$CONFIG_BACKUP" /home/user/config.json
    fi
    if [ -n "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
}
trap cleanup_verifier EXIT

run_tests() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_backup_files_state():
    backup_dir = "/home/user/backups"

    expected_kept = ["backup_2.wal", "backup_4.wal"]
    expected_deleted = ["backup_1.wal", "backup_3.wal", "backup_5.wal"]

    for filename in expected_kept:
        filepath = os.path.join(backup_dir, filename)
        assert os.path.isfile(filepath), f"Expected backup file {filename} to be kept, but it is missing."

    for filename in expected_deleted:
        filepath = os.path.join(backup_dir, filename)
        assert not os.path.exists(filepath), f"Expected backup file {filename} to be deleted, but it still exists."

def test_cleanup_report_content():
    report_path = "/home/user/cleanup_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} was not created."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "backup_1.wal: 1500000000, arch: 0x3e",
        "backup_3.wal: 1400000000, arch: 0x28",
        "backup_5.wal: 1550000000, arch: 0xf3"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in report, found {len(lines)}."

    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in the report."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    [ -f /home/user/cleanup.go ] || return 1
    [ ! -L /home/user/cleanup.go ] || return 1

    WORKDIR="$(mktemp -d /tmp/cleanup-verifier.XXXXXX)" || return 1
    CONFIG_BACKUP="$WORKDIR/original-config.json"
    cp /home/user/config.json "$CONFIG_BACKUP" || return 1

    python3 - "$WORKDIR" << 'PY' || return 1
import json
import os
import secrets
import struct
import sys

root = sys.argv[1]
backup_dir = os.path.join(root, "dynamic_backups")
report_file = os.path.join(root, "dynamic_report.txt")
os.makedirs(backup_dir)

cutoff = 1_900_000_000 + secrets.randbelow(50_000_000)
tag = secrets.token_hex(5)
entries = [
    (f"expired_a_{tag}.wal", cutoff - 12345, 0x3E, True, True, 768 * 1024 * 1024),
    (f"expired_b_{tag}.wal", cutoff - 1, 0xB7, True, True, 4096),
    (f"equal_{tag}.wal", cutoff, 0x28, False, True, 4096),
    (f"newer_{tag}.wal", cutoff + 54321, 0xF3, False, True, 768 * 1024 * 1024),
    (f"bad_magic_{tag}.wal", cutoff - 222, 0x08, False, False, 4096),
]

def write_wal(path, timestamp, arch, valid_magic, size):
    with open(path, "wb") as f:
        f.write(b"WALB" if valid_magic else b"NOPE")
        f.write(struct.pack(">I", timestamp))
        f.write(struct.pack(">I", min(size - 12, 0xFFFFFFFF)))
        f.write(b"\x7fELF" + b"\x00" * 14)
        f.write(struct.pack("<H", arch))
        f.truncate(size)

for name, timestamp, arch, expired, valid_magic, size in entries:
    write_wal(os.path.join(backup_dir, name), timestamp, arch, valid_magic, size)

non_wal = f"ignored_{tag}.bin"
write_wal(os.path.join(backup_dir, non_wal), cutoff - 999, 0x3E, True, 4096)

with open(report_file, "w", encoding="utf-8") as f:
    f.write("preexisting-marker\n")

with open("/home/user/config.json", "w", encoding="utf-8") as f:
    json.dump({
        "cutoff_time": cutoff,
        "backup_dir": backup_dir,
        "report_file": report_file,
    }, f)

manifest = {
    "backup_dir": backup_dir,
    "report_file": report_file,
    "non_wal": non_wal,
    "entries": [
        {
            "name": name,
            "timestamp": timestamp,
            "arch": arch,
            "expired": expired,
            "valid_magic": valid_magic,
            "size": size,
        }
        for name, timestamp, arch, expired, valid_magic, size in entries
    ],
}
with open(os.path.join(root, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f)
PY

    go build -o "$WORKDIR/cleanup-bin" /home/user/cleanup.go || return 1

    python3 - "$WORKDIR/cleanup-bin" << 'PY' || return 1
import resource
import subprocess
import sys
import time

proc = subprocess.Popen([sys.argv[1]])
deadline = time.monotonic() + 30
while proc.poll() is None:
    if time.monotonic() > deadline:
        proc.kill()
        proc.wait()
        raise SystemExit("cleanup program timed out")
    time.sleep(0.01)

if proc.returncode != 0:
    raise SystemExit(f"cleanup program exited with status {proc.returncode}")

max_rss_kib = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
if max_rss_kib > 131072:
    raise SystemExit(f"cleanup program used too much memory: {max_rss_kib} KiB")
PY

    python3 - "$WORKDIR/manifest.json" << 'PY' || return 1
from collections import Counter
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    manifest = json.load(f)

backup_dir = manifest["backup_dir"]
expected_report = ["preexisting-marker"]
for entry in manifest["entries"]:
    path = os.path.join(backup_dir, entry["name"])
    if entry["expired"] and entry["valid_magic"]:
        assert not os.path.exists(path), f"expired backup was not deleted: {entry['name']}"
        expected_report.append(
            f"{entry['name']}: {entry['timestamp']}, arch: 0x{entry['arch']:x}"
        )
    else:
        assert os.path.isfile(path), f"non-expired or invalid backup was deleted: {entry['name']}"
        assert os.path.getsize(path) == entry["size"], f"kept backup was modified: {entry['name']}"

non_wal_path = os.path.join(backup_dir, manifest["non_wal"])
assert os.path.isfile(non_wal_path), "non-.wal file was deleted"

assert os.path.isfile(manifest["report_file"]), "configured report was not created"
with open(manifest["report_file"], encoding="utf-8") as f:
    actual_report = [line.strip() for line in f if line.strip()]
assert Counter(actual_report) == Counter(expected_report), (
    f"unexpected dynamic report contents: {actual_report!r}"
)
PY

    cp "$CONFIG_BACKUP" /home/user/config.json || return 1
    CONFIG_BACKUP=""
    rm -rf "$WORKDIR"
    WORKDIR=""
    return 0
}

if run_tests 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
