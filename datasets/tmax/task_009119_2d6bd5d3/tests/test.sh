#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import struct
import re

def get_expected_configs():
    wal_path = "/home/user/repo_state.wal"
    artifacts_dir = "/home/user/artifacts"

    active_artifacts = {}
    with open(wal_path, "rb") as f:
        header = f.read(4)
        if header != b"ARTL":
            raise ValueError("Invalid WAL header")

        while True:
            op_bytes = f.read(1)
            if not op_bytes:
                break
            op = struct.unpack("B", op_bytes)[0]
            length = struct.unpack("B", f.read(1))[0]
            art_id = f.read(length).decode("ascii")

            if op == 1:
                active_artifacts[art_id] = True
            elif op == 0:
                active_artifacts[art_id] = False

    expected_lines = []
    pattern = re.compile(b"CONF_[A-Z_]+=[0-9]+")

    for art_id, is_active in active_artifacts.items():
        if is_active:
            bin_path = os.path.join(artifacts_dir, f"{art_id}.bin")
            if os.path.exists(bin_path):
                with open(bin_path, "rb") as f:
                    content = f.read()
                    matches = pattern.findall(content)
                    for match in matches:
                        expected_lines.append(f"{art_id}: {match.decode('ascii')}")

    expected_lines.sort()
    return expected_lines

def test_active_configs_file_exists():
    """Test that the output file was created."""
    assert os.path.isfile("/home/user/active_configs.txt"), "The output file /home/user/active_configs.txt is missing. Did you generate the report?"

def test_active_configs_content():
    """Test that the output file contains exactly the expected active configurations, correctly formatted and sorted."""
    expected_lines = get_expected_configs()

    with open("/home/user/active_configs.txt", "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of /home/user/active_configs.txt do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
