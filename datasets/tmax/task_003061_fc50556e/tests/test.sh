#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/project_dump")
IMAGES = Path("/home/user/assets/images")
LOGS = Path("/home/user/assets/logs")
CONSOLIDATED = Path("/home/user/consolidated_critical.txt")
GO_SCRIPT = Path("/home/user/split_logs.go")
PNG_MAGIC = b"\x89\x50\x4e\x47\x0d\x0a\x1a\x0a"


def expected_critical_lines():
    lines = [
        "CRITICAL Database connection lost at [REDACTED]!",
        "CRITICAL User [REDACTED] failed login",
        "CRITICAL Memory leak detected near [REDACTED]",
        "CRITICAL CPU temp high on [REDACTED]",
    ]
    lines.extend(
        f"CRITICAL subsystem failure from [REDACTED]" for _ in range(1, 31)
    )
    return lines


def clean_chunks():
    for path in LOGS.glob("critical_chunk_*.txt"):
        path.unlink()


def run_go_script():
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "go", "run", str(GO_SCRIPT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        "split_logs.go failed when executed:\n"
        + result.stdout
        + result.stderr
    )


def test_png_extraction():
    # Verify true PNGs were moved and renamed correctly.
    expected = [IMAGES / "config.txt.png", IMAGES / "unknown_blob.png"]
    for filepath in expected:
        assert filepath.is_file(), f"{filepath} is missing"
        with filepath.open("rb") as f:
            assert f.read(8) == PNG_MAGIC, f"{filepath} does not have a valid PNG header"

    # Moving, rather than copying, requires the original paths to be gone.
    assert not (PROJECT / "config.txt").exists(), "config.txt was copied instead of moved"
    assert not (PROJECT / "unknown_blob").exists(), "unknown_blob was copied instead of moved"

    # No actual PNG-header files should remain in the dump.
    for filepath in PROJECT.rglob("*"):
        if filepath.is_file():
            with filepath.open("rb") as f:
                assert f.read(8) != PNG_MAGIC, f"PNG source was not moved: {filepath}"

    # Verify the fake PNG was NOT moved.
    assert (PROJECT / "image.png").is_file(), "image.png should remain in project_dump/"
    assert not (IMAGES / "image.png.png").exists(), "fake image.png should not be moved"


def test_log_extraction_and_redaction():
    assert CONSOLIDATED.is_file(), "consolidated_critical.txt is missing"
    lines = CONSOLIDATED.read_text().splitlines()

    # Preserve the original shape and redaction checks.
    assert len(lines) == 34, f"Expected 34 critical lines, found {len(lines)}"
    ipv4_pattern = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
    for line in lines:
        assert "CRITICAL" in line, f"Line missing 'CRITICAL': {line}"
        assert not ipv4_pattern.search(line), f"IPv4 address not redacted in line: {line}"
        assert "[REDACTED]" in line, f"Line missing '[REDACTED]': {line}"

    # Require the actual extracted records in source order, not merely shaped lines.
    assert lines == expected_critical_lines(), "consolidated log contents or order are incorrect"


def test_go_script_exists_and_behaves_as_a_splitter():
    assert GO_SCRIPT.is_file(), "split_logs.go is missing"
    source = GO_SCRIPT.read_text(errors="replace")
    assert "package main" in source, "split_logs.go is not a Go main program"

    original = CONSOLIDATED.read_bytes()
    token = secrets.token_hex(16)
    probe_lines = [f"probe-{token}-{i}" for i in range(37)]

    try:
        CONSOLIDATED.write_text("\n".join(probe_lines) + "\n")
        clean_chunks()
        run_go_script()

        expected_paths = [LOGS / f"critical_chunk_{i}.txt" for i in range(1, 4)]
        actual_paths = sorted(LOGS.glob("critical_chunk_*.txt"))
        assert actual_paths == expected_paths, "Go script produced incorrect chunk filenames"

        chunks = [path.read_text().splitlines() for path in expected_paths]
        assert [len(chunk) for chunk in chunks] == [15, 15, 7]
        assert chunks[0] + chunks[1] + chunks[2] == probe_lines, (
            "Go script did not preserve arbitrary input lines in order"
        )
    finally:
        # Restore the requested final artifact and regenerate final chunks by executing Go.
        CONSOLIDATED.write_bytes(original)
        clean_chunks()
        run_go_script()

    assert CONSOLIDATED.read_bytes() == original, "Go script modified its input file"


def test_log_chunking():
    chunk1 = LOGS / "critical_chunk_1.txt"
    chunk2 = LOGS / "critical_chunk_2.txt"
    chunk3 = LOGS / "critical_chunk_3.txt"

    assert chunk1.is_file(), f"{chunk1} is missing"
    assert chunk2.is_file(), f"{chunk2} is missing"
    assert chunk3.is_file(), f"{chunk3} is missing"
    assert sorted(LOGS.glob("critical_chunk_*.txt")) == [chunk1, chunk2, chunk3]

    lines1 = chunk1.read_text().splitlines()
    lines2 = chunk2.read_text().splitlines()
    lines3 = chunk3.read_text().splitlines()
    assert len(lines1) == 15, f"Expected 15 lines in chunk 1, found {len(lines1)}"
    assert len(lines2) == 15, f"Expected 15 lines in chunk 2, found {len(lines2)}"
    assert len(lines3) == 4, f"Expected 4 lines in chunk 3, found {len(lines3)}"

    # Preserve the original final redaction checks.
    ipv4_pattern = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
    for chunk in [chunk1, chunk2, chunk3]:
        content = chunk.read_text()
        assert not ipv4_pattern.search(content), f"IPv4 address found in {chunk}"
        assert "[REDACTED]" in content, f"[REDACTED] missing in {chunk}"

    # Chunks must exactly reproduce the consolidated file in order.
    assert lines1 + lines2 + lines3 == CONSOLIDATED.read_text().splitlines()
    assert lines1 + lines2 + lines3 == expected_critical_lines()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
