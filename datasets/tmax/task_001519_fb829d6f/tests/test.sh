#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import datetime
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
from zoneinfo import ZoneInfo

FSTAB = "/home/user/mock_fstab"
VAULT = "/home/user/vault_log_fetch"
EXPECT_SCRIPT = "/home/user/auto_fetch.exp"
GO_PROGRAM = "/home/user/analyzer.go"


def get_mount_point(path=FSTAB):
    if not os.path.exists(path):
        return "/home/user/metrics_mount"
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2 and parts[0] == "/dev/sda1":
                return parts[1]
    return "/home/user/metrics_mount"


def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def run(cmd, timeout=30):
    return subprocess.run(
        cmd,
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def main():
    # Preserve the original verifier's existence and final-state assertions.
    assert os.path.isfile(EXPECT_SCRIPT), f"Expect script missing at {EXPECT_SCRIPT}"
    assert os.path.isfile(GO_PROGRAM), f"Go program missing at {GO_PROGRAM}"

    original_mount = get_mount_point()
    raw_path = os.path.join(original_mount, "raw_logs.txt")
    processed_path = os.path.join(original_mount, "processed_logs.txt")
    assert os.path.isfile(raw_path), f"raw_logs.txt missing at {raw_path}"
    assert os.path.isfile(processed_path), f"processed_logs.txt missing at {processed_path}"

    raw_content = open(raw_path, "r", encoding="utf-8").read()
    original_raw = [
        "2024-01-10T02:15:00Z | Database failover",
        "2024-01-15T14:45:00Z | API gateway timeout",
        "2024-02-01T23:59:00Z | Scheduled maintenance",
    ]
    for line in original_raw:
        assert line in raw_content, f"Missing raw log line: {line}"

    original_processed = [
        "2024-01-10 11:15:00 JST - Database failover",
        "2024-01-15 23:45:00 JST - API gateway timeout",
        "2024-02-02 08:59:00 JST - Scheduled maintenance",
    ]
    processed_content = open(processed_path, "r", encoding="utf-8").read()
    for line in original_processed:
        assert line in processed_content, f"Expected processed log line missing: {line}"
    assert read_lines(processed_path) == original_processed, "Processed output does not use the required strict line format"

    # Compile the submitted Go source independently before exercising it.
    with tempfile.TemporaryDirectory(prefix="verifier_build_") as build_dir:
        run(["go", "build", "-o", os.path.join(build_dir, "analyzer"), GO_PROGRAM], timeout=60)

    fstab_bytes = open(FSTAB, "rb").read()
    vault_bytes = open(VAULT, "rb").read()
    vault_mode = stat.S_IMODE(os.stat(VAULT).st_mode)
    dynamic_mount = "/tmp/verifier_mount_" + secrets.token_hex(12)

    try:
        # Change both the fstab mount point and service data so hardcoded files
        # cannot satisfy the behavioral checks.
        with open(FSTAB, "w", encoding="utf-8") as f:
            f.write("# dynamically supplied verifier fstab\n")
            f.write("/dev/root   /   ext4 defaults 0 0\n")
            f.write(f"  /dev/sda1\t{dynamic_mount}\text4\tdefaults,noatime 0 2\n")
            f.write("/dev/sdb1 /home/user/backup xfs defaults 0 2\n")

        base = datetime.datetime(2022, 1, 1, tzinfo=datetime.timezone.utc)
        span = 5 * 365 * 24 * 60 * 60
        moments = sorted(base + datetime.timedelta(seconds=secrets.randbelow(span)) for _ in range(4))
        messages = [f"Verifier event {i}-{secrets.token_hex(8)}" for i in range(4)]
        dynamic_raw = [
            dt.strftime("%Y-%m-%dT%H:%M:%SZ") + " | " + msg
            for dt, msg in zip(moments, messages)
        ]
        tokyo = ZoneInfo("Asia/Tokyo")
        dynamic_processed = [
            dt.astimezone(tokyo).strftime("%Y-%m-%d %H:%M:%S JST") + " - " + msg
            for dt, msg in zip(moments, messages)
        ]

        service = '''#!/usr/bin/env python3
import sys
sys.stdout.write("Username: ")
sys.stdout.flush()
user = sys.stdin.readline().strip()
sys.stdout.write("PIN: ")
sys.stdout.flush()
pin = sys.stdin.readline().strip()
if user != "sre_admin" or pin != "998877":
    print("Authentication failed.")
    raise SystemExit(1)
for line in %r:
    print(line)
''' % dynamic_raw
        with open(VAULT, "w", encoding="utf-8") as f:
            f.write(service)
        os.chmod(VAULT, 0o755)

        shutil.rmtree(dynamic_mount, ignore_errors=True)
        run(["expect", EXPECT_SCRIPT], timeout=30)

        dynamic_raw_path = os.path.join(dynamic_mount, "raw_logs.txt")
        assert os.path.isdir(dynamic_mount), "Expect script did not create the dynamically configured mount directory"
        assert os.path.isfile(dynamic_raw_path), "Expect script did not write raw_logs.txt to the fstab mount point"
        assert read_lines(dynamic_raw_path) == dynamic_raw, "Expect script did not retrieve exactly the dynamic authenticated log output"

        run(["go", "run", GO_PROGRAM], timeout=60)
        dynamic_processed_path = os.path.join(dynamic_mount, "processed_logs.txt")
        assert os.path.isfile(dynamic_processed_path), "Go program did not write processed_logs.txt to the fstab mount point"
        assert read_lines(dynamic_processed_path) == dynamic_processed, "Go output is incorrect or does not strictly match the required JST format"
    finally:
        with open(FSTAB, "wb") as f:
            f.write(fstab_bytes)
        with open(VAULT, "wb") as f:
            f.write(vault_bytes)
        os.chmod(VAULT, vault_mode)
        shutil.rmtree(dynamic_mount, ignore_errors=True)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
