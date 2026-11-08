#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import datetime
import hashlib
import os
import secrets
import subprocess
import tempfile

import pytest

CLASSIFIER = "/home/user/wal_classifier.sh"
TOKEN = "VORTEX_77X"


def run_classifier(filepath):
    return subprocess.run(
        ["bash", CLASSIFIER, filepath],
        capture_output=True,
        timeout=5,
    )


def test_wal_classifier_exists():
    assert os.path.isfile("/home/user/wal_classifier.sh"), "/home/user/wal_classifier.sh does not exist."


def test_classifier_clean_corpus():
    clean_dir = "/app/verifier/clean/"
    assert os.path.isdir(clean_dir), f"Missing verifier clean dir: {clean_dir}"

    failed_files = []
    total_files = 0
    for root, _, files in os.walk(clean_dir):
        for file in files:
            filepath = os.path.join(root, file)
            total_files += 1
            result = subprocess.run(["bash", "/home/user/wal_classifier.sh", filepath], capture_output=True)
            if result.returncode != 0:
                failed_files.append(file)

    assert len(failed_files) == 0, f"{len(failed_files)} of {total_files} clean modified/rejected. Offending files: {', '.join(failed_files)}"


def test_classifier_evil_corpus():
    evil_dir = "/app/verifier/evil/"
    assert os.path.isdir(evil_dir), f"Missing verifier evil dir: {evil_dir}"

    bypassed_files = []
    total_files = 0
    for root, _, files in os.walk(evil_dir):
        for file in files:
            filepath = os.path.join(root, file)
            total_files += 1
            result = subprocess.run(["bash", "/home/user/wal_classifier.sh", filepath], capture_output=True)
            if result.returncode == 0:
                bypassed_files.append(file)

    assert len(bypassed_files) == 0, f"{len(bypassed_files)} of {total_files} evil bypassed. Offending files: {', '.join(bypassed_files)}"


def make_valid_line(action=None):
    day = datetime.date(2020, 1, 1) + datetime.timedelta(days=secrets.randbelow(2200))
    hour = secrets.randbelow(24)
    minute = secrets.randbelow(60)
    second = secrets.randbelow(60)
    tx = secrets.randbelow(10000)
    action = action or secrets.choice(["SET", "UPDATE", "DELETE"])
    nonce = secrets.token_hex(8).upper()
    return (
        f"{day:%Y-%m-%d} {hour:02d}:{minute:02d}:{second:02d} "
        f"TX-{tx:04d} {TOKEN} {action} KEY_{nonce} VALUE_{nonce}\n"
    )


def test_generated_clean_holdout():
    with tempfile.TemporaryDirectory(prefix="wal_clean_holdout_") as directory:
        fixtures = [
            make_valid_line("SET"),
            make_valid_line("UPDATE"),
            make_valid_line("DELETE"),
            "".join(make_valid_line() for _ in range(17)),
        ]
        for index, contents in enumerate(fixtures):
            path = os.path.join(directory, f"clean_{secrets.token_hex(6)}_{index}.wal")
            with open(path, "wb") as handle:
                handle.write(contents.encode("ascii"))
            result = run_classifier(path)
            assert result.returncode == 0, (
                f"Generated valid fixture {index} was rejected with status "
                f"{result.returncode}: {result.stderr.decode(errors='replace')}"
            )


def test_generated_evil_holdout():
    base = make_valid_line("SET")
    fields = base.rstrip("\n").split(" ")

    def changed(position, value):
        altered = fields.copy()
        altered[position] = value
        return " ".join(altered) + "\n"

    invalid_lines = [
        changed(0, "2024/01/02"),
        changed(0, "2024-13-02"),
        changed(0, "2023-02-29"),
        changed(0, "2024-1-02"),
        changed(1, "24:00:00"),
        changed(1, "12:60:00"),
        changed(1, "12:00:60"),
        changed(1, "1:02:03"),
        changed(2, "TX-123"),
        changed(2, "TX-12345"),
        changed(2, "tx-1234"),
        changed(2, "TX-12A4"),
        changed(3, "VORTEX_99X"),
        changed(3, TOKEN + "X"),
        changed(4, "ESCALATE"),
        changed(4, "GET"),
        changed(4, "set"),
        changed(5, "lower_case"),
        changed(5, "KEY2"),
        changed(5, "BAD-KEY"),
        changed(6, "bad-value"),
        changed(6, "bad.value"),
        changed(6, "value with space"),
        " ".join(fields[:-1]) + "\n",
        " ".join(fields + ["EXTRA"]) + "\n",
        " " + base,
        base.rstrip("\n") + " \n",
        base.replace(" ", "  ", 1),
        base.replace(" ", "\t", 1),
        base.rstrip("\n") + "\r\n",
        base + "\n",
        base[:30] + "CORRUPTION" + base[30:],
    ]

    with tempfile.TemporaryDirectory(prefix="wal_evil_holdout_") as directory:
        for index, invalid in enumerate(invalid_lines):
            # Place each defect among fresh valid records so every line must be checked.
            contents = make_valid_line() + invalid + make_valid_line()
            path = os.path.join(directory, f"evil_{secrets.token_hex(6)}_{index}.wal")
            with open(path, "wb") as handle:
                handle.write(contents.encode("ascii"))
            result = run_classifier(path)
            assert result.returncode == 1, (
                f"Generated invalid fixture {index} returned status {result.returncode}; "
                "the required status is exactly 1"
            )


def test_clean_manifest():
    manifest_path = "/home/user/clean_manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist."

    with open(manifest_path, "r") as f:
        manifest_lines = f.read().strip().split('\n')

    manifest_dict = {}
    for line in manifest_lines:
        if not line.strip():
            continue
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            checksum, path = parts
            manifest_dict[path.strip().lstrip('*')] = checksum.strip()

    clean_dir = "/app/corpus/clean/"
    actual_files = []
    for root, _, files in os.walk(clean_dir):
        for file in files:
            actual_files.append(os.path.join(root, file))

    assert len(actual_files) > 0, "No files found in /app/corpus/clean/"

    for filepath in actual_files:
        with open(filepath, "rb") as f:
            expected_hash = hashlib.sha256(f.read()).hexdigest()

        found = False
        for m_path, m_hash in manifest_dict.items():
            if m_path.endswith(os.path.basename(filepath)):
                assert m_hash == expected_hash, f"Checksum mismatch for {filepath}. Expected {expected_hash}, got {m_hash}."
                found = True
                break
        assert found, f"File {filepath} not found in manifest."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
