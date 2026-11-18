#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import struct
import subprocess
import tarfile
import tempfile

SOURCE_PATH = "/home/user/wal_archiver.go"
EXTRACTED_CONFIGS_PATH = "/home/user/extracted_configs.txt"
ARCHIVE_PATH = "/home/user/backup.tar.gz"
CONFIG_PATH = "/home/user/backup_config.json"
BINARY_PATH = "/tmp/wal_archiver_verifier_bin"

EXPECTED_CONFIGS = [
    "MAX_CONNECTIONS=500",
    "ENABLE_LOGGING=true",
    "CACHE_SIZE=1024MB",
]

# Preserve the original final-state assertions.
assert os.path.isfile(EXTRACTED_CONFIGS_PATH), \
    f"Extracted configs file {EXTRACTED_CONFIGS_PATH} does not exist."
with open(EXTRACTED_CONFIGS_PATH, "r") as f:
    lines = [line.strip() for line in f if line.strip()]
assert lines == EXPECTED_CONFIGS, \
    f"Extracted configs do not match expected. Got: {lines}, Expected: {EXPECTED_CONFIGS}"

assert os.path.isfile(ARCHIVE_PATH), f"Archive file {ARCHIVE_PATH} does not exist."
assert tarfile.is_tarfile(ARCHIVE_PATH), f"File {ARCHIVE_PATH} is not a valid tar archive."
with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
    members = tar.getnames()
expected_members = {"backup_config.json", "extracted_configs.txt"}
actual_members = set(members)
assert actual_members == expected_members, \
    f"Archive contents do not match expected root files. Got: {actual_members}, Expected: {expected_members}"

# Exercise the compiled submission on unpredictable WAL data and paths.
token = secrets.token_hex(12)
case_dir = tempfile.mkdtemp(prefix="wal_archiver_case_")
wal_dir = os.path.join(case_dir, "wal_logs")
os.makedirs(wal_dir)
dynamic_archive = os.path.join(case_dir, "dynamic_backup.tar.gz")

values = [
    f"ALPHA_{token}=17",
    f"BETA_{token}=enabled",
    f"GAMMA_{token}=4096MB",
    f"DELTA_{token}=complete",
]

def record(record_type, payload):
    if isinstance(payload, str):
        payload = payload.encode("utf-8")
    return struct.pack(">IB", len(payload), record_type) + payload

# Names are deliberately created out of order; data records and non-WAL files
# contain distracting bytes that must not be extracted.
with open(os.path.join(wal_dir, "020_second.wal"), "wb") as f:
    f.write(record(2, b"ignored-data-" + token.encode()))
    f.write(record(1, values[2]))
with open(os.path.join(wal_dir, "003_first.wal"), "wb") as f:
    f.write(record(2, ("NOT_A_CONFIG_" + token).encode()))
    f.write(record(1, values[0]))
    f.write(record(2, b"\x00\xff\x01\x02"))
    f.write(record(1, values[1]))
with open(os.path.join(wal_dir, "100_last.wal"), "wb") as f:
    f.write(record(1, values[3]))
with open(os.path.join(wal_dir, "001_not_wal.txt"), "wb") as f:
    f.write(record(1, f"MUST_NOT_APPEAR_{token}"))

config_bytes = json.dumps({
    "wal_dir": wal_dir,
    "archive_path": dynamic_archive,
}, separators=(",", ":")).encode("utf-8")
with open(CONFIG_PATH, "wb") as f:
    f.write(config_bytes)

if os.path.exists(dynamic_archive):
    os.unlink(dynamic_archive)

result = subprocess.run(
    [BINARY_PATH],
    cwd="/home/user",
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    timeout=30,
)
assert result.returncode == 0, \
    f"Compiled program failed with code {result.returncode}: {result.stderr.decode(errors='replace')}"

assert os.path.isfile(EXTRACTED_CONFIGS_PATH), "Program did not create extracted_configs.txt"
with open(EXTRACTED_CONFIGS_PATH, "rb") as f:
    extracted_bytes = f.read()
try:
    dynamic_lines = extracted_bytes.decode("utf-8").splitlines()
except UnicodeDecodeError as exc:
    raise AssertionError("extracted_configs.txt is not valid UTF-8") from exc
assert dynamic_lines == values, \
    f"Program did not parse dynamic WAL records in filename/record order. Got: {dynamic_lines}, Expected: {values}"

assert os.path.isfile(dynamic_archive), \
    f"Program did not create the configured archive {dynamic_archive}"
assert tarfile.is_tarfile(dynamic_archive), "Configured archive is not a valid tar archive"
with tarfile.open(dynamic_archive, "r:gz") as tar:
    archive_members = tar.getmembers()
    names = [member.name for member in archive_members]
    assert len(archive_members) == 2 and set(names) == expected_members, \
        f"Dynamic archive must contain exactly the two root files; got {names}"
    for member in archive_members:
        assert member.isfile(), f"Archive member {member.name} is not a regular file"
    archived_config = tar.extractfile("backup_config.json").read()
    archived_extracted = tar.extractfile("extracted_configs.txt").read()

assert archived_config == config_bytes, \
    "Archived backup_config.json is not the original configuration file"
assert archived_extracted == extracted_bytes, \
    "Archived extracted_configs.txt does not match the generated output file"
PY_EOF

if [ -f /home/user/wal_archiver.go ] \
   && go build -o /tmp/wal_archiver_verifier_bin /home/user/wal_archiver.go \
   && python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
