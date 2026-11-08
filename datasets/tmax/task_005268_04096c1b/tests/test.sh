#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest


def test_recover_cpp_exists():
    """Verify that the C++ program recover.cpp was created."""
    file_path = "/home/user/recover.cpp"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."


def test_restored_json_valid():
    """Verify that restored.json exists and contains the correct JSON data."""
    file_path = "/home/user/artifacts/restored.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    assert "repository" in data, "JSON missing 'repository' key."
    assert data["repository"] == "core-binaries", "Incorrect 'repository' value."
    assert "artifacts" in data, "JSON missing 'artifacts' key."

    found = False
    for artifact in data["artifacts"]:
        if artifact.get("id") == "linux-kernel-6.5-rc1":
            found = True
            assert artifact.get("sha256_checksum") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "Incorrect checksum in JSON."
            break

    assert found, "Artifact 'linux-kernel-6.5-rc1' not found in restored JSON."

    expected = {
        "repository": "core-binaries",
        "backup_version": 1,
        "artifacts": [
            {"id": "glibc-2.38", "sha256_checksum": "a1b2c3d4e5f60789"},
            {"id": "linux-kernel-6.5-rc1", "sha256_checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
            {"id": "gcc-13.2", "sha256_checksum": "ffeeddccbbaa9988"},
        ],
    }
    assert data == expected, "restored.json does not contain the complete recovered document."


def test_flag_txt_correct():
    """Verify that flag.txt exists and contains the correct checksum."""
    file_path = "/home/user/artifacts/flag.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_checksum = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    assert content == expected_checksum, f"Expected {expected_checksum} in flag.txt, but got {content}."
TEST_EOF

result=0
(
    set -e

    test -f /home/user/recover.cpp
    g++ -std=c++17 -O2 /home/user/recover.cpp -o /tmp/recover_submission

    rm -f /home/user/artifacts/restored.json
    cd /home/user
    timeout 10s /tmp/recover_submission

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

    dynamic_digest="$(python3 - <<'PY'
import hashlib
import json
import random
import secrets
import struct

checksum = secrets.token_hex(32)
document = {
    "repository": "dynamic-" + secrets.token_hex(8),
    "backup_version": 73,
    "metadata": {"nonce": secrets.token_hex(24), "enabled": True},
    "artifacts": [
        {"id": "alpha", "sha256_checksum": secrets.token_hex(32)},
        {"id": "linux-kernel-6.5-rc1", "sha256_checksum": checksum},
        {"id": "omega", "sha256_checksum": secrets.token_hex(32)},
    ],
}
payload = json.dumps(document, separators=(",", ":"), sort_keys=True).encode("utf-8")

sizes = [1, 7, 19, 33, 5, 48, 11]
parts = []
pos = 0
i = 0
while pos < len(payload):
    size = sizes[i % len(sizes)]
    parts.append(payload[pos:pos + size])
    pos += size
    i += 1

def chunk(chunk_id, data):
    return b"CHNK" + struct.pack("<II", chunk_id, len(data)) + data

# Put every genuine chunk first, but in a non-ID order. Later chunks repeat
# IDs with different payloads, so only the first occurrence is valid.
order = list(range(len(parts)))
random.SystemRandom().shuffle(order)
sequence = [chunk(i, parts[i]) for i in order]
for i in reversed(order):
    if i % 2 == 0:
        sequence.append(chunk(i, secrets.token_bytes(max(1, len(parts[i])))))

with open("/home/user/artifacts/corrupted_backup.bin", "wb") as f:
    f.write(b"".join(sequence))

print(hashlib.sha256(payload).hexdigest())
PY
)"

    rm -f /home/user/artifacts/restored.json
    timeout 10s /tmp/recover_submission
    test -f /home/user/artifacts/restored.json
    actual_digest="$(sha256sum /home/user/artifacts/restored.json | awk '{print $1}')"
    test "$actual_digest" = "$dynamic_digest"
) && result=1

echo "$result" > /logs/verifier/reward.txt
