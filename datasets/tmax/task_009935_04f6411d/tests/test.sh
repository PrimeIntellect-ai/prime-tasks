#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import tarfile
from collections import Counter
from pathlib import Path

import pytest


def test_tracker_cpp_exists():
    tracker_cpp = "/home/user/tracker.cpp"
    assert os.path.isfile(tracker_cpp), f"Expected C++ source file {tracker_cpp} is missing."


def test_tarball_exists():
    tarball = "/home/user/remote_archive/sync_data.tar.gz"
    assert os.path.isfile(tarball), f"Expected tarball {tarball} is missing."


def test_tarball_contents():
    tarball_path = "/home/user/remote_archive/sync_data.tar.gz"
    assert os.path.isfile(tarball_path), f"Cannot test contents, {tarball_path} does not exist."

    expected_csv = (
        "Timestamp,KeyA,KeyB\n"
        "2023-11-01T08:00:00Z,MAX_CONNECTIONS,MAX_CONNECTIONS\n"
        "2023-11-01T09:00:00Z,WORKER_THREADS,WORKER_THREADS\n"
        "2023-11-01T10:30:00Z,CACHE_SIZE,LOG_LEVEL"
    )

    found_csv = False
    csv_content = ""

    try:
        with tarfile.open(tarball_path, "r:gz") as tar:
            for member in tar.getmembers():
                if member.name.endswith("aligned_features.csv"):
                    found_csv = True
                    f = tar.extractfile(member)
                    if f is not None:
                        csv_content = f.read().decode("utf-8").strip()
                    break
    except tarfile.TarError as e:
        pytest.fail(f"Failed to open or read tarball {tarball_path}: {e}")

    assert found_csv, "aligned_features.csv was not found inside the tarball."

    # Normalize line endings for comparison
    normalized_actual = "\n".join([line.strip() for line in csv_content.splitlines() if line.strip()])
    normalized_expected = "\n".join([line.strip() for line in expected_csv.splitlines() if line.strip()])

    assert normalized_actual == normalized_expected, (
        "The contents of aligned_features.csv inside the tarball do not match the expected output.\n"
        f"Expected:\n{normalized_expected}\n\nActual:\n{normalized_actual}"
    )


def test_tracker_compiles_and_processes_fresh_logs():
    source = Path("/home/user/tracker.cpp")
    binary = Path("/tmp/tracker_verifier_binary")
    log_a = Path("/home/user/logs/serverA.log")
    log_b = Path("/home/user/logs/serverB.log")
    output = Path("/home/user/aligned_features.csv")

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", str(source), "-o", str(binary)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "tracker.cpp did not compile successfully:\n" + compile_result.stderr
    )
    assert binary.is_file(), "Compiling tracker.cpp did not produce an executable."

    original_a = log_a.read_bytes()
    original_b = log_b.read_bytes()
    output_existed = output.exists()
    original_output = output.read_bytes() if output_existed else None

    nonce = secrets.token_hex(6).upper()
    common = [
        ("2026-02-03T04:05:06Z", f"ALPHA_{nonce}", f"REMOTE_{nonce}"),
        ("2026-02-03T07:18:29Z", f"BETA_{nonce}", f"SECOND_{nonce}"),
        ("2026-02-04T10:11:12Z", f"GAMMA_{nonce}", f"THIRD_{nonce}"),
    ]

    a_text = (
        f"[{common[1][0]}] {common[1][1]}=value_a2\n"
        f"[2026-02-03T01:02:03Z] ONLY_A_{nonce}=unused\n"
        f"[{common[0][0]}] {common[0][1]}=value_a1\n"
        f"[{common[2][0]}] {common[2][1]}=value_a3\n"
    )
    b_text = (
        f"[{common[2][0]}] {common[2][2]}=value_b3\n"
        f"[{common[0][0]}] {common[0][2]}=value_b1\n"
        f"[2026-02-05T13:14:15Z] ONLY_B_{nonce}=unused\n"
        f"[{common[1][0]}] {common[1][2]}=value_b2\n"
    )

    try:
        log_a.write_text(a_text, encoding="utf-8")
        log_b.write_text(b_text, encoding="utf-8")
        if output.exists():
            output.unlink()

        run_result = subprocess.run(
            [str(binary)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert run_result.returncode == 0, (
            "The compiled tracker failed when run on fresh logs:\n" + run_result.stderr
        )
        assert output.is_file(), (
            "Running the compiled tracker did not create /home/user/aligned_features.csv."
        )

        lines = output.read_text(encoding="utf-8").splitlines()
        assert lines and lines[0] == "Timestamp,KeyA,KeyB", (
            "The generated CSV does not have the exact required header."
        )
        assert len(lines) == len(common) + 1, (
            "The generated CSV must contain exactly the timestamps shared by both fresh logs."
        )
        assert all(", " not in line for line in lines), (
            "The generated CSV contains spaces after commas."
        )

        actual_rows = []
        for line in lines[1:]:
            fields = line.split(",")
            assert len(fields) == 3, f"Malformed CSV data row: {line!r}"
            actual_rows.append(tuple(fields))

        expected_rows = [(timestamp, key_a, key_b) for timestamp, key_a, key_b in common]
        assert Counter(actual_rows) == Counter(expected_rows), (
            "The compiled tracker did not derive the matching timestamps and keys from fresh logs.\n"
            f"Expected rows: {expected_rows}\nActual rows: {actual_rows}"
        )
    finally:
        log_a.write_bytes(original_a)
        log_b.write_bytes(original_b)
        if output_existed:
            output.write_bytes(original_output)
        elif output.exists():
            output.unlink()
        if binary.exists():
            binary.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
