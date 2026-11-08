#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_incoming_artifacts_empty():
    incoming_dir = "/home/user/incoming_artifacts"
    assert os.path.isdir(incoming_dir), f"Directory missing: {incoming_dir}"
    assert len(os.listdir(incoming_dir)) == 0, f"Directory {incoming_dir} should be empty"

def test_processed_artifacts():
    processed_dir = "/home/user/processed"
    assert os.path.isdir(processed_dir), f"Directory missing: {processed_dir}"
    expected_files = ["safe_app.tar.gz", "safe_data.zip"]
    for file in expected_files:
        filepath = os.path.join(processed_dir, file)
        assert os.path.isfile(filepath), f"File missing in processed: {filepath}"

def test_quarantine_artifacts():
    quarantine_dir = "/home/user/quarantine"
    assert os.path.isdir(quarantine_dir), f"Directory missing: {quarantine_dir}"
    expected_files = ["slip_tar.tar.gz", "slip_zip.zip", "bad_archive.tar.gz", "broken_data.zip"]
    for file in expected_files:
        filepath = os.path.join(quarantine_dir, file)
        assert os.path.isfile(filepath), f"File missing in quarantine: {filepath}"

def test_extracted_safe_artifacts():
    expected_paths = [
        "/home/user/safe_artifacts/safe_app/bin/run.sh",
        "/home/user/safe_artifacts/safe_data/data/info.txt"
    ]
    for path in expected_paths:
        assert os.path.isfile(path), f"Extracted file missing: {path}"

def test_artifact_audit_log():
    log_file = "/home/user/artifact_audit.log"
    assert os.path.isfile(log_file), f"Log file missing: {log_file}"

    with open(log_file, "r") as f:
        log_lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_entries = {
        "safe_app.tar.gz": "SAFE | N/A",
        "safe_data.zip": "SAFE | N/A",
        "slip_tar.tar.gz": "MALICIOUS | ../evil.sh",
        "slip_zip.zip": "MALICIOUS | /etc/shadow",
        "bad_archive.tar.gz": "CORRUPT | N/A",
        "broken_data.zip": "CORRUPT | N/A"
    }

    parsed_entries = {}
    for line in log_lines:
        parts = [p.strip() for p in line.split("|")]
        assert len(parts) == 3, f"Malformed log line: {line}"
        filename, status, detail = parts
        parsed_entries[filename] = f"{status} | {detail}"

    for filename, expected_status_detail in expected_entries.items():
        assert filename in parsed_entries, f"Missing log entry for {filename}"
        assert parsed_entries[filename] == expected_status_detail, f"Incorrect log entry for {filename}: expected {expected_status_detail}, got {parsed_entries[filename]}"
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_dynamic_audit.py
import hashlib
import io
import os
import shutil
import subprocess
import tarfile
import uuid
import zipfile

HOME = "/home/user"
SCRIPT = f"{HOME}/audit.sh"
INCOMING = f"{HOME}/incoming_artifacts"
SAFE = f"{HOME}/safe_artifacts"
QUARANTINE = f"{HOME}/quarantine"
PROCESSED = f"{HOME}/processed"
LOG = f"{HOME}/artifact_audit.log"


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def test_dynamic_archive_processing():
    assert os.path.isfile(SCRIPT), f"Required Bash script missing: {SCRIPT}"
    syntax = subprocess.run(
        ["bash", "-n", SCRIPT], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=10
    )
    assert syntax.returncode == 0, f"audit.sh is not valid Bash syntax:\n{syntax.stdout}"

    for path in (INCOMING, SAFE, QUARANTINE, PROCESSED):
        shutil.rmtree(path, ignore_errors=True)
        os.makedirs(path, mode=0o777)
    if os.path.lexists(LOG):
        os.remove(LOG)

    token = uuid.uuid4().hex
    names = {
        "safe_tar": f"safe_tar_{token}.tar.gz",
        "safe_zip": f"safe_zip_{token}.zip",
        "mal_tar": f"traversal_{token}.tar.gz",
        "mal_zip": f"absolute_{token}.zip",
        "bad_tar": f"damaged_tar_{token}.tar.gz",
        "bad_zip": f"damaged_zip_{token}.zip",
    }
    safe_tar_member = f"pkg_{token}/bin/tool.txt"
    safe_zip_member = f"dataset_{token}/record.txt"
    safe_tar_data = (f"tar payload {token}\n").encode()
    safe_zip_data = (f"zip payload {token}\n").encode()
    traversal_member = f"../escape_{token}.sh"
    absolute_member = f"/tmp/audit_abs_{token}"

    with tarfile.open(os.path.join(INCOMING, names["safe_tar"]), "w:gz") as tf:
        info = tarfile.TarInfo(safe_tar_member)
        info.size = len(safe_tar_data)
        tf.addfile(info, io.BytesIO(safe_tar_data))

    with zipfile.ZipFile(os.path.join(INCOMING, names["safe_zip"]), "w") as zf:
        zf.writestr(safe_zip_member, safe_zip_data)

    with tarfile.open(os.path.join(INCOMING, names["mal_tar"]), "w:gz") as tf:
        normal = tarfile.TarInfo(f"normal_{token}.txt")
        normal_data = b"normal"
        normal.size = len(normal_data)
        tf.addfile(normal, io.BytesIO(normal_data))
        evil = tarfile.TarInfo(traversal_member)
        evil_data = b"must not be extracted"
        evil.size = len(evil_data)
        tf.addfile(evil, io.BytesIO(evil_data))

    with zipfile.ZipFile(os.path.join(INCOMING, names["mal_zip"]), "w") as zf:
        zf.writestr(f"good_{token}.txt", b"good")
        zf.writestr(absolute_member, b"must not be extracted")

    with open(os.path.join(INCOMING, names["bad_tar"]), "wb") as f:
        f.write((f"not a tar archive {token}").encode())
    with open(os.path.join(INCOMING, names["bad_zip"]), "wb") as f:
        f.write((f"not a zip archive {token}").encode())

    original_hashes = {
        name: digest(os.path.join(INCOMING, name)) for name in names.values()
    }

    outside_candidates = [
        absolute_member,
        os.path.join(SAFE, f"escape_{token}.sh"),
        os.path.join(HOME, f"escape_{token}.sh"),
    ]
    for path in outside_candidates:
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)

    result = subprocess.run(
        ["bash", SCRIPT], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"audit.sh failed on generated archives:\n{result.stdout}"

    assert os.path.isdir(INCOMING)
    assert os.listdir(INCOMING) == [], "audit.sh did not process every generated archive"

    expected_processed = {names["safe_tar"], names["safe_zip"]}
    expected_quarantined = {
        names["mal_tar"], names["mal_zip"], names["bad_tar"], names["bad_zip"]
    }
    assert set(os.listdir(PROCESSED)) == expected_processed
    assert set(os.listdir(QUARANTINE)) == expected_quarantined

    for name in expected_processed:
        path = os.path.join(PROCESSED, name)
        assert os.path.isfile(path)
        assert digest(path) == original_hashes[name], f"Processed archive was replaced or altered: {name}"
    for name in expected_quarantined:
        path = os.path.join(QUARANTINE, name)
        assert os.path.isfile(path)
        assert digest(path) == original_hashes[name], f"Quarantined archive was replaced or altered: {name}"

    tar_base = names["safe_tar"][:-7]
    zip_base = names["safe_zip"][:-4]
    tar_output = os.path.join(SAFE, tar_base, safe_tar_member)
    zip_output = os.path.join(SAFE, zip_base, safe_zip_member)
    with open(tar_output, "rb") as f:
        assert f.read() == safe_tar_data
    with open(zip_output, "rb") as f:
        assert f.read() == safe_zip_data

    assert not os.path.exists(os.path.join(SAFE, names["mal_tar"][:-7]))
    assert not os.path.exists(os.path.join(SAFE, names["mal_zip"][:-4]))
    for path in outside_candidates:
        assert not os.path.lexists(path), f"Malicious member was extracted outside its destination: {path}"

    assert os.path.isfile(LOG), "audit.sh did not create the audit log"
    with open(LOG, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\n") for line in f]
    assert len(lines) == 6, f"Expected exactly one log line per archive, got: {lines!r}"

    expected_lines = {
        f'{names["safe_tar"]} | SAFE | N/A',
        f'{names["safe_zip"]} | SAFE | N/A',
        f'{names["mal_tar"]} | MALICIOUS | {traversal_member}',
        f'{names["mal_zip"]} | MALICIOUS | {absolute_member}',
        f'{names["bad_tar"]} | CORRUPT | N/A',
        f'{names["bad_zip"]} | CORRUPT | N/A',
    }
    assert set(lines) == expected_lines, f"Incorrect audit log lines: {lines!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py /tmp/test_dynamic_audit.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
