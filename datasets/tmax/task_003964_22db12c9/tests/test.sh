#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import glob
import os
import secrets
import struct
import subprocess
import tempfile
import uuid

SCRIPT_PATH = "/home/user/detect_slip.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_detector(file_path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, file_path],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.ibk.gz"))
    assert len(clean_files) > 0, f"No clean corpus files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for file_path in clean_files:
        result = run_detector(file_path)
        if result.returncode != 0 or "SAFE" not in result.stdout.strip():
            failed_files.append(os.path.basename(file_path))

    assert not failed_files, (
        f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly flagged as MALICIOUS or failed. "
        f"Offending files: {', '.join(failed_files)}"
    )


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.ibk.gz"))
    assert len(evil_files) > 0, f"No evil corpus files found in {EVIL_CORPUS_DIR}"

    failed_files = []
    for file_path in evil_files:
        result = run_detector(file_path)
        if result.returncode != 1 or "MALICIOUS" not in result.stdout.strip():
            failed_files.append(os.path.basename(file_path))

    assert not failed_files, (
        f"{len(failed_files)} of {len(evil_files)} evil files bypassed detection. "
        f"Offending files: {', '.join(failed_files)}"
    )


def write_ibk(file_path, records):
    with gzip.open(file_path, "wb") as stream:
        for path, data, incremental_flag in records:
            encoded_path = path.encode("utf-8")
            stream.write(b"IBK1")
            stream.write(struct.pack("<H", len(encoded_path)))
            stream.write(encoded_path)
            stream.write(struct.pack("<I", len(data)))
            stream.write(data)
            stream.write(struct.pack("<B", incremental_flag))


def read_exact(stream, size):
    value = stream.read(size)
    assert len(value) == size, "Generated IBK archive was unexpectedly truncated"
    return value


def path_is_malicious(path):
    return (
        path.startswith("/")
        or "../" in path
        or "..\\" in path
        or path == ".."
        or path.endswith("/..")
        or path.endswith("\\..")
    )


def independently_classify_archive(file_path):
    malicious = False
    with gzip.open(file_path, "rb") as stream:
        while True:
            magic = stream.read(4)
            if magic == b"":
                break
            assert magic == b"IBK1", "Generated archive has invalid record magic"
            path_length = struct.unpack("<H", read_exact(stream, 2))[0]
            path = read_exact(stream, path_length).decode("utf-8")
            data_length = struct.unpack("<I", read_exact(stream, 4))[0]
            read_exact(stream, data_length)
            read_exact(stream, 1)
            malicious = malicious or path_is_malicious(path)
    return malicious


def test_unseen_generated_archives():
    token = secrets.token_hex(12)
    safe_a = f"store/{token}/document.txt"
    safe_b = f"config/{token}.json"
    safe_c = f"windows\\folder\\{token}.dat"

    # Dangerous-looking strings in payloads ensure the detector parses record
    # boundaries instead of searching all decompressed bytes for traversal text.
    dangerous_payload = (
        b"../../etc/shadow /root/secret dir/.. test/..\\..\\system32"
        + os.urandom(4096)
    )

    cases = [
        [(safe_a, dangerous_payload, 0)],
        [(safe_a, os.urandom(257), 0), (safe_b, dangerous_payload, 1), (safe_c, b"ok", 0)],
        [(safe_a, os.urandom(513), 0), (f"/{token}/absolute.txt", b"x", 1)],
        [(safe_b, b"safe", 0), (f"area/{token}/../secret", b"x", 0)],
        [(safe_c, b"safe", 1), (f"area\\{token}\\..\\secret", b"x", 0)],
        [(safe_a, b"safe", 0), (f"area/{token}/..", b"x", 0)],
        [(safe_b, b"safe", 0), ("..", b"x", 1)],
        [(safe_a, os.urandom(262144), 0), (f"later/{token}/../../target", b"x", 0)],
    ]

    with tempfile.TemporaryDirectory(prefix="ibk_verifier_") as temp_dir:
        archive_paths = []
        for records in cases:
            archive_path = os.path.join(temp_dir, f"{uuid.uuid4().hex}.ibk.gz")
            write_ibk(archive_path, records)
            archive_paths.append(archive_path)

        # Do not encode classifications in filenames or directories, and derive
        # each expected answer by independently parsing the generated IBK file.
        for archive_path in archive_paths:
            expected_malicious = independently_classify_archive(archive_path)
            result = run_detector(archive_path)
            if expected_malicious:
                assert result.returncode == 1, result.stderr
                assert "MALICIOUS" in result.stdout.strip(), result.stdout
            else:
                assert result.returncode == 0, result.stderr
                assert "SAFE" in result.stdout.strip(), result.stdout
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
