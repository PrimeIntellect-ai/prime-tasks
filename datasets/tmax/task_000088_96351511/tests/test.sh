#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
import time

DATASET_DIR = "/home/user/dataset"
FILES_TXT = os.path.join(DATASET_DIR, "files.txt")
CONFIG_INI = os.path.join(DATASET_DIR, "config.ini")
PARSER_CPP = "/home/user/parser.cpp"
PARSER_BIN = "/home/user/parser"
MANIFEST_CSV = "/home/user/manifest.csv"


def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def test_files_txt_cleaned():
    assert os.path.isfile(FILES_TXT), f"{FILES_TXT} is missing."
    with open(FILES_TXT, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "C:\\dataset\\" not in content, "Windows paths were not removed from files.txt"
    assert "/home/user/dataset/alpha.dat" in content, "Cleaned path for alpha.dat not found in files.txt"
    assert "/home/user/dataset/beta.dat" in content, "Cleaned path for beta.dat not found in files.txt"
    assert "/home/user/dataset/gamma.dat" in content, "Cleaned path for gamma.dat not found in files.txt"

    # Every original list entry must have been transformed, including corrupt.dat.
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert lines == [
        "/home/user/dataset/alpha.dat",
        "/home/user/dataset/beta.dat",
        "/home/user/dataset/gamma.dat",
        "/home/user/dataset/corrupt.dat",
    ], f"files.txt has incorrect or incompletely transformed entries: {lines!r}"
    assert all("\\" not in line for line in lines), "Backslashes remain in files.txt"


def test_parser_exists_and_compiled():
    assert os.path.isfile(PARSER_CPP), f"Source file {PARSER_CPP} is missing."
    assert os.path.isfile(PARSER_BIN), f"Compiled binary {PARSER_BIN} is missing."
    assert os.access(PARSER_BIN, os.X_OK), f"{PARSER_BIN} is not executable."
    with open(PARSER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PARSER_BIN} is not a compiled ELF executable."


def test_parser_uses_locking():
    assert os.path.isfile(PARSER_CPP), f"Source file {PARSER_CPP} is missing."
    with open(PARSER_CPP, "r") as f:
        content = f.read()

    assert "flock" in content or "fcntl" in content, "C++ source does not appear to use explicit file locking (flock or fcntl)."


def test_manifest_csv_correctness():
    assert os.path.isfile(MANIFEST_CSV), f"{MANIFEST_CSV} was not generated."

    with open(MANIFEST_CSV, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_files = ["alpha.dat", "beta.dat", "gamma.dat"]
    expected_rows = []

    for filename in expected_files:
        filepath = os.path.join(DATASET_DIR, filename)
        assert os.path.isfile(filepath), f"Expected data file {filepath} is missing."

        with open(filepath, "rb") as f:
            header_data = f.read(16)
            _, sensor_id, timestamp = struct.unpack("<4s I Q", header_data)

        file_hash = get_sha256(filepath)
        expected_rows.append(f"{filename},{sensor_id},{timestamp},{file_hash}")

    assert len(lines) == 3, f"Expected exactly 3 rows in manifest.csv, found {len(lines)}."

    for expected_row in expected_rows:
        assert expected_row in lines, f"Expected row '{expected_row}' not found in manifest.csv."

    for line in lines:
        assert "corrupt.dat" not in line, "corrupt.dat should have been skipped but was found in manifest.csv."


def run_with_external_manifest_lock(executable, expected_rows):
    try:
        os.remove(MANIFEST_CSV)
    except FileNotFoundError:
        pass

    lock_fd = os.open(MANIFEST_CSV, os.O_RDWR | os.O_CREAT | os.O_TRUNC, 0o666)
    proc = None
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        proc = subprocess.Popen([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(0.6)
        assert proc.poll() is None, (
            f"{executable} exited while manifest.csv was exclusively locked; "
            "its writes do not use a cooperating explicit file lock"
        )
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        stdout, stderr = proc.communicate(timeout=15)
        assert proc.returncode == 0, (
            f"{executable} failed with status {proc.returncode}; "
            f"stdout={stdout.decode(errors='replace')!r}, stderr={stderr.decode(errors='replace')!r}"
        )
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except OSError:
            pass
        os.close(lock_fd)
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()

    assert os.path.isfile(MANIFEST_CSV), "Parser did not create manifest.csv"
    with open(MANIFEST_CSV, "r") as f:
        rows = [line.strip() for line in f if line.strip()]
    assert sorted(rows) == sorted(expected_rows), (
        f"Parser output for generated test data was incorrect. Expected {expected_rows!r}, got {rows!r}"
    )


def test_execute_binary_and_rebuilt_source_on_generated_inputs():
    original_files = open(FILES_TXT, "rb").read()
    original_config = open(CONFIG_INI, "rb").read()
    manifest_existed = os.path.exists(MANIFEST_CSV)
    original_manifest = open(MANIFEST_CSV, "rb").read() if manifest_existed else None

    token = secrets.token_hex(4)
    magic = secrets.token_hex(2).upper().encode("ascii")
    fixtures = [
        (f"verify_{token}_one.dat", magic, secrets.randbelow(2**32), secrets.randbelow(2**63), os.urandom(37)),
        (f"verify_{token}_two.dat", magic, secrets.randbelow(2**32), secrets.randbelow(2**63), os.urandom(113)),
        (f"verify_{token}_bad.dat", b"BAD!" if magic != b"BAD!" else b"NOPE", 777, 888, os.urandom(51)),
    ]
    fixture_paths = [os.path.join(DATASET_DIR, item[0]) for item in fixtures]

    try:
        with open(CONFIG_INI, "w") as f:
            f.write("[SENSOR]\nVERSION=9.9\nMAGIC_BYTES=" + magic.decode("ascii") + "\nAUTHOR=VERIFIER\n")

        with open(FILES_TXT, "w") as f:
            for path in fixture_paths:
                f.write(path + "\n")

        expected_rows = []
        for filename, file_magic, sensor_id, timestamp, payload in fixtures:
            path = os.path.join(DATASET_DIR, filename)
            with open(path, "wb") as f:
                f.write(struct.pack("<4sIQ", file_magic, sensor_id, timestamp))
                f.write(payload)
            if file_magic == magic:
                expected_rows.append(f"{filename},{sensor_id},{timestamp},{get_sha256(path)}")

        # Exercise the submitted executable, including its real cooperation with flock.
        run_with_external_manifest_lock(PARSER_BIN, expected_rows)

        # Recompile and exercise parser.cpp so a dummy/unrelated binary or comment-only
        # source cannot satisfy the task.
        rebuilt = os.path.join(tempfile.gettempdir(), f"parser_rebuilt_{token}")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", PARSER_CPP, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "parser.cpp could not be compiled: " + compile_result.stderr.decode(errors="replace")
        )
        run_with_external_manifest_lock(rebuilt, expected_rows)
        os.remove(rebuilt)
    finally:
        for path in fixture_paths:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        with open(FILES_TXT, "wb") as f:
            f.write(original_files)
        with open(CONFIG_INI, "wb") as f:
            f.write(original_config)
        if manifest_existed:
            with open(MANIFEST_CSV, "wb") as f:
                f.write(original_manifest)
        else:
            try:
                os.remove(MANIFEST_CSV)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
