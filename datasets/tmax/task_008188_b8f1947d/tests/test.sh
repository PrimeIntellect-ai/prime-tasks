#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest


def test_registry_exists_and_content():
    registry_path = "/home/user/repo/registry.tsv"
    assert os.path.isfile(registry_path), f"Registry file {registry_path} does not exist."

    expected_rows = [
        "OriginalName\tNewPath\tArchitecture\tVersion",
        "auth_module.elf\t/home/user/repo/x86_64/auth_module_v3.2.0.elf\tx86_64\t3.2.0",
        "core_engine.elf\t/home/user/repo/x86_64/core_engine_v1.0.5.elf\tx86_64\t1.0.5",
        "net_worker.elf\t/home/user/repo/aarch64/net_worker_v0.9.9-beta.elf\taarch64\t0.9.9-beta",
        "orphan_bin.elf\t/home/user/repo/x86_64/orphan_bin_v1.1.1.elf\tx86_64\t1.1.1"
    ]

    with open(registry_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == len(expected_rows), f"Expected {len(expected_rows)} rows in registry.tsv, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_rows)):
        assert actual == expected, f"Row {i+1} in registry.tsv is incorrect.\nExpected: '{expected}'\nActual: '{actual}'"


def test_elf_files_moved_and_renamed():
    expected_files = [
        "/home/user/repo/x86_64/auth_module_v3.2.0.elf",
        "/home/user/repo/x86_64/core_engine_v1.0.5.elf",
        "/home/user/repo/aarch64/net_worker_v0.9.9-beta.elf",
        "/home/user/repo/x86_64/orphan_bin_v1.1.1.elf"
    ]

    for filepath in expected_files:
        assert os.path.isfile(filepath), f"Expected ELF file is missing: {filepath}"

        # Verify it's actually an ELF file
        with open(filepath, "rb") as f:
            header = f.read(4)
            assert header == b"\x7fELF", f"File {filepath} is not a valid ELF."


def test_moved_elf_contents_are_preserved():
    expected = {
        "/home/user/repo/x86_64/auth_module_v3.2.0.elf": ("/bin/ls", None),
        "/home/user/repo/x86_64/core_engine_v1.0.5.elf": ("/bin/true", None),
        "/home/user/repo/aarch64/net_worker_v0.9.9-beta.elf": ("/bin/true", (18, 0xB7)),
        "/home/user/repo/x86_64/orphan_bin_v1.1.1.elf": ("/bin/pwd", None),
    }

    for destination, (source, patch) in expected.items():
        with open(source, "rb") as f:
            expected_bytes = bytearray(f.read())
        if patch is not None:
            offset, value = patch
            expected_bytes[offset] = value

        with open(destination, "rb") as f:
            actual_bytes = f.read()

        assert actual_bytes == bytes(expected_bytes), (
            f"ELF content at {destination} does not match the original incoming binary."
        )


def test_invalid_file_ignored():
    # readme.elf was invalid and should not have been moved into the repo
    for root, dirs, files in os.walk("/home/user/repo"):
        for file in files:
            assert "readme" not in file, f"Invalid file readme.elf was processed and found in repo: {os.path.join(root, file)}"
            assert "9.9.9" not in file, f"Invalid file version 9.9.9 was processed and found in repo: {os.path.join(root, file)}"


def test_original_files_removed_from_incoming():
    # The task says "Move and rename", so the original valid ELFs should no longer be in incoming.
    moved_originals = [
        "auth_module.elf",
        "core_engine.elf",
        "net_worker.elf",
        "orphan_bin.elf"
    ]
    for filename in moved_originals:
        filepath = os.path.join("/home/user/incoming", filename)
        assert not os.path.exists(filepath), f"Original file {filepath} was not moved (it still exists in incoming)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
