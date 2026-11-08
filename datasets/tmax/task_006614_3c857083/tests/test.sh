#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

PROJECT = Path("/home/user/archiver")
CARGO_TOML = PROJECT / "Cargo.toml"
MAIN_RS = PROJECT / "src/main.rs"
LOG_PATH = Path("/home/user/backup_data/system.log")
MANIFEST_PATH = Path("/home/user/archive_manifest.csv")


def test_rust_project_exists():
    assert os.path.isfile(CARGO_TOML), f"Rust project not found: {CARGO_TOML} is missing."
    assert os.path.isfile(MAIN_RS), f"Rust source file not found: {MAIN_RS} is missing."


def test_archive_manifest_exists():
    assert os.path.isfile(MANIFEST_PATH), f"Output file {MANIFEST_PATH} was not created."


def test_archive_manifest_content():
    expected_lines = [
        "/etc/hostname,27",
        "/var/log/auth.log,6735",
        "/home/user/.bashrc,3700"
    ]

    with open(MANIFEST_PATH, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in manifest, but found {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual.strip()}'."


def test_source_uses_streaming_io():
    sources = "\n".join(
        path.read_text(errors="replace") for path in (PROJECT / "src").rglob("*.rs")
    )
    streaming_markers = (
        "BufReader",
        "read_line(",
        ".lines(",
        "read_until(",
        "fill_buf(",
        ".read(",
    )
    assert any(marker in sources for marker in streaming_markers), \
        "Rust source does not appear to use a streaming input API."
    assert not re.search(r"\bread_to_(?:string|end)\s*\(|(?:std::)?fs::read(?:_to_string)?\s*\(", sources), \
        "The log must be streamed rather than loaded into memory in full."


def test_compiled_program_parses_runtime_log():
    subprocess.run(
        ["cargo", "clean", "--manifest-path", str(CARGO_TOML)],
        cwd=PROJECT, check=True, timeout=120, capture_output=True, text=True
    )
    subprocess.run(
        ["cargo", "build", "--manifest-path", str(CARGO_TOML), "--bin", "archiver"],
        cwd=PROJECT, check=True, timeout=120, capture_output=True, text=True
    )

    binary = PROJECT / "target/debug/archiver"
    assert binary.is_file(), f"Compiled archiver executable not found at {binary}."
    assert os.access(binary, os.X_OK), f"Compiled artifact {binary} is not executable."

    token = secrets.token_hex(6)
    entries = [
        (f"/tmp/archive_{token}_a.bin", secrets.randbelow(0x700000) + 0x10000),
        (f"/var/tmp/archive_{token}_b.log", secrets.randbelow(0x700000) + 0x10000),
        (f"/home/user/archive_{token}_c.dat", secrets.randbelow(0x700000) + 0x10000),
        (f"/opt/archive_{token}_d.img", secrets.randbelow(0x700000) + 0x10000),
    ]
    runtime_log = ["2042-01-02 03:04:00 INFO Runtime verification started"]
    for index, (path, value) in enumerate(entries, start=1):
        runtime_log.append(f"2042-01-02 03:04:{index:02d} [ARCHIVE_REQ] {path} 0x{value:X}")
        runtime_log.append(f"2042-01-02 03:05:{index:02d} DEBUG unrelated record {token}")
    expected = [f"{path},{value}" for path, value in entries]

    original_log = LOG_PATH.read_bytes()
    original_manifest = MANIFEST_PATH.read_bytes() if MANIFEST_PATH.exists() else None
    try:
        LOG_PATH.write_text("\n".join(runtime_log) + "\n")
        if MANIFEST_PATH.exists():
            MANIFEST_PATH.unlink()

        subprocess.run(
            [str(binary)], cwd=PROJECT, check=True, timeout=30,
            capture_output=True, text=True
        )

        assert MANIFEST_PATH.is_file(), "Running the compiled Rust program did not create the manifest."
        actual = MANIFEST_PATH.read_text().strip().splitlines()
        assert actual == expected, f"Compiled program produced {actual!r}, expected {expected!r}."
    finally:
        LOG_PATH.write_bytes(original_log)
        if original_manifest is None:
            if MANIFEST_PATH.exists():
                MANIFEST_PATH.unlink()
        else:
            MANIFEST_PATH.write_bytes(original_manifest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
