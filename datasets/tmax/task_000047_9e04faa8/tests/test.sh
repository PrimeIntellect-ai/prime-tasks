#!/bin/bash
mkdir -p /logs/verifier

run_verifier() (
    set -e

    test -f /home/user/extractor.go
    GO111MODULE=off go build -o /tmp/submission-extractor /home/user/extractor.go
    test -x /tmp/submission-extractor

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_safe_files_extracted():
    expected_files = {
        "/home/user/extracted/data/sensor1.csv": b"timestamp,value\n1,10.5",
        "/home/user/extracted/data/sensor2.csv": b"timestamp,value\n1,20.1",
        "/home/user/extracted/notes.txt": b"experiment notes",
        "/home/user/extracted/nested/safe.txt": b"safe content"
    }

    for path, expected_content in expected_files.items():
        assert os.path.exists(path), f"Safe file {path} was not extracted."
        assert os.path.isfile(path), f"{path} is not a file."
        with open(path, "rb") as f:
            content = f.read()
        assert content == expected_content, f"Content of {path} does not match expected."

def test_malicious_files_not_extracted():
    malicious_paths = [
        "/home/user/overwritten_secret.txt",
        "/home/user/etc/shadow",
        "/home/user/extracted/../overwritten_secret.txt",
        "/home/user/extracted/data/../../etc/shadow"
    ]

    for path in malicious_paths:
        normalized_path = os.path.normpath(path)
        assert not os.path.exists(normalized_path), f"Malicious file was extracted to {normalized_path}"

def test_malicious_log_contents():
    log_path = "/home/user/malicious.log"
    assert os.path.exists(log_path), f"Log file {log_path} was not created."
    assert os.path.isfile(log_path), f"{log_path} is not a file."

    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "../overwritten_secret.txt",
        "data/../../etc/shadow"
    ]

    assert lines == expected_lines, f"Contents of {log_path} do not match the expected malicious paths. Got: {lines}"

def test_no_extra_files_in_extracted():
    expected_paths = {
        "/home/user/extracted/data/sensor1.csv",
        "/home/user/extracted/data/sensor2.csv",
        "/home/user/extracted/notes.txt",
        "/home/user/extracted/nested/safe.txt"
    }

    actual_files = set()
    for root, _, files in os.walk("/home/user/extracted"):
        for file in files:
            actual_files.add(os.path.normpath(os.path.join(root, file)))

    extra_files = actual_files - expected_paths
    assert not extra_files, f"Found unexpected files in /home/user/extracted/: {extra_files}"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

    cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_extractor.py
import os
import secrets
import shutil
import struct
import subprocess

home = "/home/user"
outdir = os.path.join(home, "extracted")
archive = os.path.join(home, "dataset.bin")
log_path = os.path.join(home, "malicious.log")
token = secrets.token_hex(12)

safe_records = [
    (f"group_{token}/raw.bin", os.urandom(31)),
    (f"group_{token}/inner/../normalized.txt", ("dynamic-" + token).encode()),
]
malicious_records = [
    (f"../escape_{token}.txt", b"must-not-escape-one"),
    (f"inside/../../escape2_{token}.txt", b"must-not-escape-two"),
]
records = [safe_records[0], malicious_records[0], safe_records[1], malicious_records[1]]

shutil.rmtree(outdir, ignore_errors=True)
os.mkdir(outdir, 0o777)
os.chmod(outdir, 0o777)
try:
    os.remove(log_path)
except FileNotFoundError:
    pass

outside_paths = [
    os.path.join(home, f"escape_{token}.txt"),
    os.path.join(home, f"escape2_{token}.txt"),
]
for path in outside_paths:
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)

with open(archive, "wb") as f:
    f.write(b"DATA")
    for path, content in records:
        encoded = path.encode("utf-8")
        f.write(struct.pack("<H", len(encoded)))
        f.write(encoded)
        f.write(struct.pack("<I", len(content)))
        f.write(content)
os.chmod(archive, 0o666)

result = subprocess.run(
    ["runuser", "-u", "user", "--", "timeout", "15", "/tmp/submission-extractor"],
    cwd=home,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    timeout=20,
)
assert result.returncode == 0, (
    f"compiled extractor failed with status {result.returncode}; "
    f"stdout={result.stdout!r}, stderr={result.stderr!r}"
)

expected_files = {
    os.path.normpath(os.path.join(outdir, path)): content
    for path, content in safe_records
}
for path, expected in expected_files.items():
    assert os.path.isfile(path), f"Dynamic safe file was not extracted: {path}"
    with open(path, "rb") as f:
        assert f.read() == expected, f"Wrong dynamic content in {path}"

actual_files = set()
for root, _, files in os.walk(outdir):
    for name in files:
        actual_files.add(os.path.normpath(os.path.join(root, name)))
assert actual_files == set(expected_files), (
    f"Dynamic extraction produced the wrong file set: {actual_files}"
)

for path in outside_paths:
    assert not os.path.exists(path), f"Traversal path was extracted outside the target: {path}"

assert os.path.isfile(log_path), "Extractor did not create malicious.log"
with open(log_path, "r", encoding="utf-8") as f:
    logged = f.read().splitlines()
assert logged == [path for path, _ in malicious_records], (
    f"Wrong dynamic malicious.log contents: {logged}"
)
DYNAMIC_EOF

    python3 /tmp/test_dynamic_extractor.py
)

if run_verifier; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
