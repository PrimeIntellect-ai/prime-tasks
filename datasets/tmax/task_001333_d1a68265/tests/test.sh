#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import hashlib
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

FILTER = "/home/user/filter"
SOURCE = "/home/user/filter.c"
OLD_LOGS = Path("/home/user/old_logs")
NEW_LOGS = Path("/home/user/new_logs")
MANIFEST = Path("/home/user/manifest.sha256")


def exercise_filter(executable):
    token = secrets.token_hex(24)
    long_debug = "[DEBUG] " + token + ("D" * 3000) + "\n"
    long_kept = "[INFO] " + token + ("K" * 3000) + "\n"
    input_text = (
        "[DEBUG] discard-" + token + "\n"
        + "[DEBUG]X keep-" + token + "\n"
        + "prefix [DEBUG] keep-" + token + "\n"
        + long_debug
        + long_kept
        + "[DEBUG]\n"
        + "final-" + token
    )
    expected = (
        "[DEBUG]X keep-" + token + "\n"
        + "prefix [DEBUG] keep-" + token + "\n"
        + long_kept
        + "[DEBUG]\n"
        + "final-" + token
    ).encode("utf-8")
    result = subprocess.run(
        [executable],
        input=input_text.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, f"{executable} exited with {result.returncode}: {result.stderr!r}"
    assert result.stdout == expected, f"{executable} does not implement the required exact line filtering"


def expected_outputs():
    expected = {}
    inputs = sorted(OLD_LOGS.glob("*.log.gz"))
    assert inputs, "No input .log.gz files found"
    for source in inputs:
        with gzip.open(source, "rb") as stream:
            latin1_data = stream.read()
        text = latin1_data.decode("iso-8859-1")
        filtered = "".join(line for line in text.splitlines(keepends=True) if not line.startswith("[DEBUG] "))
        output_name = source.name[:-7] + ".filtered.log.gz"
        expected[output_name] = filtered.encode("utf-8")
    return expected


def test_filter_executable():
    assert os.path.exists(FILTER), "/home/user/filter does not exist"
    assert os.access(FILTER, os.X_OK), "/home/user/filter is not executable"
    assert os.path.isfile(FILTER), "/home/user/filter is not a regular executable file"
    with open(FILTER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/filter is not a compiled ELF executable"
    exercise_filter(FILTER)


def test_filter_source():
    assert os.path.isfile(SOURCE), "/home/user/filter.c is missing"
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "filter")
        result = subprocess.run(
            ["gcc", "-std=gnu11", "-O2", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert result.returncode == 0, f"/home/user/filter.c does not compile: {result.stderr.decode(errors='replace')}"
        exercise_filter(rebuilt)


def test_new_logs_exist():
    assert os.path.isdir("/home/user/new_logs"), "/home/user/new_logs directory is missing"
    assert os.path.isfile("/home/user/new_logs/server1.filtered.log.gz"), "server1.filtered.log.gz is missing"
    assert os.path.isfile("/home/user/new_logs/server2.filtered.log.gz"), "server2.filtered.log.gz is missing"
    for filename in expected_outputs():
        assert (NEW_LOGS / filename).is_file(), f"{filename} is missing"


def test_log_contents():
    log1_path = "/home/user/new_logs/server1.filtered.log.gz"
    log2_path = "/home/user/new_logs/server2.filtered.log.gz"

    try:
        with gzip.open(log1_path, 'rb') as f:
            content1 = f.read().decode('utf-8')
    except Exception as e:
        assert False, f"Failed to read and decode {log1_path} as UTF-8: {e}"

    try:
        with gzip.open(log2_path, 'rb') as f:
            content2 = f.read().decode('utf-8')
    except Exception as e:
        assert False, f"Failed to read and decode {log2_path} as UTF-8: {e}"

    assert "[DEBUG] " not in content1, "server1.filtered.log.gz contains [DEBUG] lines"
    assert "[DEBUG] " not in content2, "server2.filtered.log.gz contains [DEBUG] lines"

    assert "Falla crítica en la conexión" in content1, "server1.filtered.log.gz missing expected UTF-8 content"
    assert "Autenticación fallida para el usuario" in content2, "server2.filtered.log.gz missing expected UTF-8 content"
    assert "Starting server" in content1, "server1.filtered.log.gz missing expected content"
    assert "Cache initialized" in content2, "server2.filtered.log.gz missing expected content"

    for filename, expected in expected_outputs().items():
        path = NEW_LOGS / filename
        try:
            with gzip.open(path, "rb") as stream:
                actual = stream.read()
            actual.decode("utf-8")
        except Exception as e:
            assert False, f"Failed to read and decode {path} as UTF-8: {e}"
        assert actual == expected, f"{filename} is not the exact converted and filtered input"


def test_manifest_sha256():
    manifest_path = "/home/user/manifest.sha256"
    assert os.path.isfile(manifest_path), "/home/user/manifest.sha256 is missing"

    with open(manifest_path, 'r') as f:
        manifest_lines = f.read().strip().split('\n')

    manifest_dict = {}
    for line in manifest_lines:
        if not line.strip():
            continue
        parts = line.split(None, 1)
        if len(parts) == 2:
            filename = parts[1].strip()
            if filename.startswith('*'):
                filename = filename[1:]
            manifest_dict[filename] = parts[0].strip()

    assert "server1.filtered.log.gz" in manifest_dict, "server1.filtered.log.gz missing from manifest (ensure basenames are used)"
    assert "server2.filtered.log.gz" in manifest_dict, "server2.filtered.log.gz missing from manifest (ensure basenames are used)"

    for filename in ["server1.filtered.log.gz", "server2.filtered.log.gz"]:
        expected_hash = manifest_dict[filename]
        filepath = os.path.join("/home/user/new_logs", filename)
        assert os.path.isfile(filepath), f"File {filename} in manifest does not exist in /home/user/new_logs"
        with open(filepath, 'rb') as f:
            actual_hash = hashlib.sha256(f.read()).hexdigest()
        assert actual_hash == expected_hash, f"Hash mismatch for {filename} in manifest"

    nonempty_lines = [line for line in manifest_lines if line.strip()]
    strict_entries = {}
    pattern = re.compile(r"^([0-9a-fA-F]{64}) ([ *])([^/]+)$")
    for line in nonempty_lines:
        match = pattern.fullmatch(line)
        assert match, f"Manifest line is not in standard sha256sum basename format: {line!r}"
        digest, _, filename = match.groups()
        assert filename not in strict_entries, f"Duplicate manifest entry for {filename}"
        strict_entries[filename] = digest.lower()

    output_files = {path.name for path in NEW_LOGS.iterdir() if path.is_file()}
    required_files = set(expected_outputs())
    assert required_files <= output_files, "Not all input logs were processed"
    assert set(strict_entries) == output_files, "Manifest must contain exactly all files in /home/user/new_logs"
    for filename, digest in strict_entries.items():
        actual = hashlib.sha256((NEW_LOGS / filename).read_bytes()).hexdigest()
        assert digest == actual, f"Hash mismatch for {filename} in manifest"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
