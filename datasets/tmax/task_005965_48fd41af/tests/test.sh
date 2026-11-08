#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import stat
import subprocess
import time
from pathlib import Path

import pytest

DOCS_DIR = Path("/home/user/docs")
ENCODER = Path("/home/user/encoder.py")
PROCESS_SCRIPT = Path("/home/user/process_docs.sh")
COMPILED = Path("/home/user/compiled_docs.txt")
ARCHIVE = Path("/home/user/compressed_archive.b64")


def expected_results():
    expected_text = ""
    expected_lines = []
    if DOCS_DIR.is_dir():
        files = sorted([f for f in os.listdir(DOCS_DIR) if f.endswith(".txt")])
        for filename in files:
            content = (DOCS_DIR / filename).read_bytes()
            text = content.decode("windows-1252")
            expected_text += text
            expected_lines.append(
                base64.b64encode(text[::-1].encode("utf-8")).decode("ascii")
            )
    return expected_text, "\n".join(expected_lines) + "\n"


def test_encoder_script_exists_and_uses_flock():
    script_path = "/home/user/encoder.py"
    assert os.path.isfile(script_path), f"The file {script_path} does not exist."
    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "fcntl.flock" in content, f"The script {script_path} does not seem to use fcntl.flock."


def test_process_docs_script_exists():
    script_path = "/home/user/process_docs.sh"
    assert os.path.isfile(script_path), f"The file {script_path} does not exist."


def test_compiled_docs_content():
    compiled_path = "/home/user/compiled_docs.txt"
    assert os.path.isfile(compiled_path), f"The file {compiled_path} does not exist."

    expected_text, _ = expected_results()
    with open(compiled_path, "r", encoding="utf-8") as f:
        actual_text = f.read()

    assert actual_text == expected_text, "The content of compiled_docs.txt does not match the expected concatenated UTF-8 text."


def test_compressed_archive_content():
    archive_path = "/home/user/compressed_archive.b64"
    assert os.path.isfile(archive_path), f"The file {archive_path} does not exist."

    _, expected_output = expected_results()
    with open(archive_path, "r", encoding="utf-8") as f:
        actual_output = f.read()

    assert actual_output.strip() == expected_output.strip(), "The content of compressed_archive.b64 does not match the expected base64 output."


def test_encoder_executes_encoding_append_and_exclusive_lock(tmp_path):
    first = tmp_path / "one.txt"
    second = tmp_path / "two.txt"
    first.write_bytes(b"First: \x80")
    second.write_bytes(b"Second: \x99")
    texts = [first.read_bytes().decode("windows-1252"), second.read_bytes().decode("windows-1252")]
    expected_lines = [
        base64.b64encode(text[::-1].encode("utf-8")).decode("ascii")
        for text in texts
    ]

    existed = COMPILED.exists()
    old_bytes = COMPILED.read_bytes() if existed else None
    try:
        import fcntl

        with open(COMPILED, "w+b") as locked_file:
            fcntl.flock(locked_file.fileno(), fcntl.LOCK_EX)
            proc = subprocess.Popen(
                ["python3", str(ENCODER)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert proc.stdin is not None
            proc.stdin.write(f"{first}\n{second}\n")
            proc.stdin.close()

            time.sleep(0.75)
            assert proc.poll() is None, "encoder.py did not wait for the exclusive lock on compiled_docs.txt"
            fcntl.flock(locked_file.fileno(), fcntl.LOCK_UN)

            proc.wait(timeout=10)
            assert proc.stdout is not None and proc.stderr is not None
            stdout = proc.stdout.read()
            stderr = proc.stderr.read()

        assert proc.returncode == 0, stderr
        assert stdout.splitlines() == expected_lines
        assert COMPILED.read_text(encoding="utf-8") == "".join(texts)
    finally:
        if existed:
            COMPILED.write_bytes(old_bytes)
        elif COMPILED.exists():
            COMPILED.unlink()


def test_process_script_finds_sorts_pipes_and_redirects():
    original_bytes = ENCODER.read_bytes()
    original_mode = stat.S_IMODE(ENCODER.stat().st_mode)
    received = Path("/tmp/process_docs_received.txt")
    if received.exists():
        received.unlink()

    probe = '''#!/usr/bin/env python3
import sys
from pathlib import Path
paths = sys.stdin.read()
Path("/tmp/process_docs_received.txt").write_text(paths, encoding="utf-8")
for path in paths.splitlines():
    print("PROBE:" + path)
'''

    try:
        ENCODER.write_text(probe, encoding="utf-8")
        ENCODER.chmod(0o755)
        result = subprocess.run(
            ["bash", str(PROCESS_SCRIPT)],
            text=True,
            capture_output=True,
            timeout=15,
        )
        assert result.returncode == 0, result.stderr

        expected_paths = sorted(str(path) for path in DOCS_DIR.glob("*.txt"))
        assert received.is_file(), "process_docs.sh did not invoke /home/user/encoder.py"
        assert received.read_text(encoding="utf-8").splitlines() == expected_paths
        assert ARCHIVE.read_text(encoding="utf-8").splitlines() == [
            "PROBE:" + path for path in expected_paths
        ]
    finally:
        ENCODER.write_bytes(original_bytes)
        ENCODER.chmod(original_mode)
        if received.exists():
            received.unlink()


def test_process_script_end_to_end_from_clean_outputs():
    if COMPILED.exists():
        COMPILED.unlink()
    if ARCHIVE.exists():
        ARCHIVE.unlink()

    result = subprocess.run(
        ["bash", str(PROCESS_SCRIPT)],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr

    expected_text, expected_archive = expected_results()
    assert COMPILED.is_file()
    assert ARCHIVE.is_file()
    assert COMPILED.read_text(encoding="utf-8") == expected_text
    assert ARCHIVE.read_text(encoding="utf-8").strip() == expected_archive.strip()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
