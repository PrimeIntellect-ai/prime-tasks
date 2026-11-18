#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import uuid
from pathlib import Path

import pytest

SCRIPT = Path("/home/user/release_builder.sh")
V1_PROTO = Path("/home/user/src/protos/v1/user.proto")
V2_DIR = Path("/home/user/src/protos/v2")
V2_PROTO = V2_DIR / "user.proto"
INDEX_FILE = Path("/home/user/proto_index.txt")
MOCK_FILE = Path("/home/user/ws_mock_stream.jsonl")


def expected_migration(source):
    migrated, package_count = re.subn(
        r"(?m)(\bpackage\s+)v1(\s*;)",
        r"\g<1>v2\g<2>",
        source,
    )
    assert package_count == 1, "Test input must contain exactly one package v1 declaration"

    field_pattern = re.compile(
        r"(?m)^(\s*)int32(\s+)([A-Za-z_][A-Za-z0-9_]*_id)(\s*=\s*\d+\s*;)"
    )
    return field_pattern.sub(
        lambda match: match.group(1) + "string" + match.group(2)
        + match.group(3) + match.group(4),
        migrated,
    )


def clear_outputs():
    if V2_DIR.exists():
        shutil.rmtree(V2_DIR)
    for path in (INDEX_FILE, MOCK_FILE):
        if path.exists() or path.is_symlink():
            path.unlink()


def run_builder():
    clear_outputs()
    result = subprocess.run(
        [str(SCRIPT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"release_builder.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_complete_migration(source):
    assert V2_PROTO.is_file(), f"Failed: v2 proto file {V2_PROTO} does not exist."
    actual = V2_PROTO.read_text()
    expected = expected_migration(source)
    assert actual == expected, (
        "Failed: v2/user.proto is not the complete text-based migration of v1/user.proto."
    )


def test_00_builder_exists_is_executable_and_performs_migration():
    assert SCRIPT.is_file(), f"Failed: required script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Failed: required script {SCRIPT} is not executable."

    original = V1_PROTO.read_text()
    canary = uuid.uuid4().hex

    try:
        # Remove all deliverables and require the submitted executable to recreate them.
        run_builder()
        assert_complete_migration(original)

        expected_index = sorted(
            str(path) for path in Path("/home/user/src/protos").rglob("*.proto")
        )
        assert INDEX_FILE.is_file(), "Failed: builder did not create proto_index.txt"
        assert INDEX_FILE.read_text().splitlines() == expected_index, (
            "Failed: builder did not index every .proto file in sorted order"
        )
        assert MOCK_FILE.is_file(), "Failed: builder did not create ws_mock_stream.jsonl"

        # Exercise the migration on an input unknown when the submission was written.
        augmented = original + (
            f"\nmessage Verification_{canary} {{\n"
            f"  int32 runtime_{canary}_id = 101;\n"
            f"  int32 runtime_{canary}_count = 102;\n"
            f"  string existing_{canary}_id = 103;\n"
            f"}}\n"
        )
        V1_PROTO.write_text(augmented)
        run_builder()
        assert_complete_migration(augmented)
    finally:
        V1_PROTO.parent.mkdir(parents=True, exist_ok=True)
        V1_PROTO.write_text(original)
        # Leave the required final artifacts generated from the original input.
        if SCRIPT.is_file() and os.access(SCRIPT, os.X_OK):
            clear_outputs()
            subprocess.run(
                [str(SCRIPT)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )

    assert SCRIPT.is_file(), "Failed: builder removed itself during execution."
    assert os.access(SCRIPT, os.X_OK), "Failed: builder is no longer executable."
    assert_complete_migration(original)


def test_v2_proto_exists_and_migrated():
    """Test that the v2 proto file exists and has the correct schema migrations."""
    v2_proto = "/home/user/src/protos/v2/user.proto"
    assert os.path.isfile(v2_proto), f"Failed: v2 proto file {v2_proto} does not exist."

    with open(v2_proto, 'r') as f:
        content = f.read()

    # Check package update
    assert re.search(r"package\s+v2\s*;", content), "Failed: package not updated to v2 in v2/user.proto"

    # Check user_id migrated to string
    assert re.search(r"string\s+user_id\s*=\s*1\s*;", content), "Failed: user_id not migrated to string in v2/user.proto"

    # Check group_id migrated to string
    assert re.search(r"string\s+group_id\s*=\s*3\s*;", content), "Failed: group_id not migrated to string in v2/user.proto"

    # Check age is still int32
    assert re.search(r"int32\s+age\s*=\s*5\s*;", content), "Failed: age was modified but shouldn't have been in v2/user.proto"


def test_proto_index():
    """Test that the proto index file contains the correct sorted paths."""
    index_file = "/home/user/proto_index.txt"
    assert os.path.isfile(index_file), f"Failed: index file {index_file} does not exist."

    with open(index_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/src/protos/v1/user.proto",
        "/home/user/src/protos/v2/user.proto"
    ]

    # The list must be sorted alphabetically and match the expected exact paths
    assert lines == sorted(expected_lines), f"Failed: {index_file} does not contain the expected sorted paths. Got: {lines}"


def test_ws_mock_stream():
    """Test that the WebSocket mock stream file is valid JSONL and has correct data."""
    mock_file = "/home/user/ws_mock_stream.jsonl"
    assert os.path.isfile(mock_file), f"Failed: mock stream file {mock_file} does not exist."

    with open(mock_file, 'r') as f:
        physical_lines = f.read().splitlines()

    assert len(physical_lines) == 3, f"Failed: {mock_file} should contain exactly 3 lines of JSON."
    assert all(line.strip() for line in physical_lines), f"Failed: {mock_file} contains a blank JSONL line."
    lines = [line.strip() for line in physical_lines]

    expected_data = [
        {"user_id": "uuid-1", "username": "alpha", "group_id": "group-1", "is_active": True},
        {"user_id": "uuid-2", "username": "beta", "group_id": "group-2", "is_active": False},
        {"user_id": "uuid-3", "username": "gamma", "group_id": "group-3", "is_active": True}
    ]

    for i, (line, expected) in enumerate(zip(lines, expected_data), 1):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Failed: Line {i} in {mock_file} is not valid JSON.")

        assert parsed == expected, f"Failed: JSON row {i} incorrect. Expected {expected}, got {parsed}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
