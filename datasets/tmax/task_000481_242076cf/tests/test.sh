#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import struct
import subprocess
import tempfile
import time
import urllib.request
import zipfile

import pytest

CURATOR = "/home/user/curator"
SOURCE = "/home/user/curator.cpp"


def fetch(url):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200, f"Expected status 200, got {response.status}"
        return response.read()


def test_nginx_proxy_working_and_returns_actual_bundle():
    """Nginx must proxy the real upstream bundle, not merely return nonempty data."""
    proxy_url = "http://localhost:8080/artifacts/bundle.zip"
    upstream_url = "http://localhost:8081/bundle.zip"
    try:
        proxied = fetch(proxy_url)
        upstream = fetch(upstream_url)
    except Exception as e:
        pytest.fail(f"Failed to download through proxy or upstream: {e}")

    assert len(proxied) > 0, "Downloaded bundle.zip is empty"
    assert proxied == upstream, "Proxy response is not the actual upstream bundle.zip"

    with zipfile.ZipFile(io.BytesIO(proxied)) as archive:
        assert archive.testzip() is None, "Proxied bundle.zip is corrupt"
        assert "archive.tar.gz" in archive.namelist(), "Proxied bundle has unexpected contents"


def test_curator_binary_exists_and_executable():
    """The requested source and compiled C++ ELF executable must exist."""
    assert os.path.isfile(SOURCE), f"C++ source {SOURCE} does not exist."
    assert os.path.isfile(CURATOR), f"Compiled binary {CURATOR} does not exist."
    assert os.access(CURATOR, os.X_OK), f"Compiled binary {CURATOR} is not executable."
    with open(CURATOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "curator is not a compiled ELF binary"


def make_wal(path, records):
    with open(path, "wb") as f:
        for record in records:
            encoded = record.encode("utf-16le")
            f.write(struct.pack("<I", len(encoded)))
            f.write(encoded)


def run_and_check(binary, wal, cwd, expected):
    result = subprocess.run(
        [binary, wal], cwd=cwd, capture_output=True, timeout=3
    )
    assert result.returncode == 0, (
        f"Curator execution failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr.decode('utf-8', errors='replace')}"
    )
    try:
        output = result.stdout.decode("utf-8", errors="strict").splitlines()
    except UnicodeDecodeError as e:
        pytest.fail(f"Curator output is not valid UTF-8: {e}")
    assert output == expected, f"Expected valid ELF paths {expected!r}, got {output!r}"


def test_curator_parses_utf16le_and_filters_by_elf_magic():
    """Exercise both the submitted executable and a fresh build on unpredictable records."""
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory() as work:
        os.makedirs(os.path.join(work, "bins", "nested"))
        valid_unicode = f"bins/nested/{token}_café_😀.elf"
        valid_ascii = f"bins/{token}_second.bin"
        invalid_magic = f"bins/{token}_not_elf.bin"
        missing = f"bins/{token}_missing.elf"

        for relative in (valid_unicode, valid_ascii):
            with open(os.path.join(work, relative), "wb") as f:
                f.write(b"\x7fELF" + os.urandom(12))
        with open(os.path.join(work, invalid_magic), "wb") as f:
            f.write(b"NOTELF" + os.urandom(12))

        records = [invalid_magic, valid_unicode, missing, valid_ascii]
        wal = os.path.join(work, "journal.wal")
        make_wal(wal, records)
        expected = [valid_unicode, valid_ascii]

        run_and_check(CURATOR, wal, work, expected)

        rebuilt = os.path.join(work, "curator-rebuilt")
        compile_result = subprocess.run(
            ["g++", "-O2", "-std=c++17", SOURCE, "-o", rebuilt],
            capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, (
            "curator.cpp is not a buildable C++ implementation:\n" + compile_result.stderr
        )
        with open(rebuilt, "rb") as f:
            assert f.read(4) == b"\x7fELF"
        run_and_check(rebuilt, wal, work, expected)


def test_curator_execution_time_metric():
    """The original large WAL metric must be fast and produce all correct records."""
    wal_path = "/app/large_journal.wal"
    assert os.path.isfile(wal_path), f"Benchmark file {wal_path} is missing."

    with tempfile.TemporaryDirectory() as work:
        elf_dir = os.path.join(work, "elf_files")
        os.makedirs(elf_dir)
        with open(os.path.join(elf_dir, "dummy.elf"), "wb") as f:
            f.write(b"\x7fELF\x02\x01\x01\x00")

        start_time = time.perf_counter()
        result = subprocess.run(
            [CURATOR, wal_path], cwd=work, capture_output=True, text=True, timeout=3
        )
        execution_time = time.perf_counter() - start_time

    assert result.returncode == 0, (
        f"Curator execution failed with return code {result.returncode}.\nStderr: {result.stderr}"
    )
    threshold = 0.5
    assert execution_time <= threshold, (
        f"Metric failed: Execution time was {execution_time:.4f} seconds, "
        f"which exceeds the threshold of {threshold} seconds."
    )
    assert len(result.stdout.strip()) > 0, "Curator produced no output. It should print valid paths."
    assert result.stdout.splitlines() == ["elf_files/dummy.elf"] * 1000, (
        "Curator did not parse and emit every valid benchmark WAL record correctly"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
