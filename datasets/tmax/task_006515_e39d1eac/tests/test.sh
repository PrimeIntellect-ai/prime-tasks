#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import tarfile
import uuid
import zipfile


def get_sha256(filepath):
    hash_sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_sha256.update(chunk)
    return hash_sha256.hexdigest()


def parse_ingest(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    result = {}
    for record in re.findall(r"\[START\](.*?)\[END\]", text, re.S):
        file_match = re.search(r"^File:\s*(.+?)\s*$", record, re.M)
        hash_match = re.search(r"^SHA256:\s*([0-9a-fA-F]{64})\s*$", record, re.M)
        if file_match and hash_match:
            result[file_match.group(1)] = hash_match.group(1).lower()
    return result


def test_final_state():
    curated_dir = "/home/user/curated"
    raw_dir = "/home/user/raw_drop"

    file1 = os.path.join(curated_dir, "x86_64", "app", "app-x86_64-v1.tar.gz")
    file2 = os.path.join(curated_dir, "arm64", "app", "app-arm64-v1.zip")

    assert os.path.isfile(file1), f"Expected curated file not found: {file1}"
    assert os.path.isfile(file2), f"Expected curated file not found: {file2}"

    hash1 = get_sha256(file1)
    hash2 = get_sha256(file2)

    csv_path = os.path.join(curated_dir, "verified_manifest.csv")
    assert os.path.isfile(csv_path), f"CSV manifest not found: {csv_path}"

    with open(csv_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) == 3, f"Expected 3 lines in CSV (header + 2 rows), got {len(lines)}"
    assert lines[0] == "filename,architecture,project,sha256", f"CSV header incorrect: {lines[0]}"

    expected_row1 = f"app-arm64-v1.zip,arm64,app,{hash2}"
    expected_row2 = f"app-x86_64-v1.tar.gz,x86_64,app,{hash1}"

    assert lines[1] == expected_row1, f"CSV row 1 incorrect. Expected '{expected_row1}', got '{lines[1]}'"
    assert lines[2] == expected_row2, f"CSV row 2 incorrect. Expected '{expected_row2}', got '{lines[2]}'"

    # Check that corrupt/bitrot files were excluded from the curated directory
    for root, dirs, files in os.walk(curated_dir):
        assert "lib-x86_64-v2.tar.gz" not in files, "Corrupted archive 'lib-x86_64-v2.tar.gz' was incorrectly moved to curated directory"
        assert "tools-arm64-v3.tar.gz" not in files, "Bit-rot archive 'tools-arm64-v3.tar.gz' was incorrectly moved to curated directory"

    # Tie the curated artifacts to the supplied manifest and ingestion records.
    expected_manifest = [
        {"file": "app-x86_64-v1.tar.gz", "project": "app", "arch": "x86_64"},
        {"file": "app-arm64-v1.zip", "project": "app", "arch": "arm64"},
        {"file": "lib-x86_64-v2.tar.gz", "project": "lib", "arch": "x86_64"},
        {"file": "tools-arm64-v3.tar.gz", "project": "tools", "arch": "arm64"},
    ]
    with open(os.path.join(raw_dir, "vendor_manifest.json"), "r", encoding="utf-8") as f:
        assert json.load(f) == expected_manifest, "The vendor manifest was modified or not parsed from the supplied input"

    ingest_hashes = parse_ingest(os.path.join(raw_dir, "ingest.log"))
    assert set(ingest_hashes) == {entry["file"] for entry in expected_manifest}, "Ingestion records are missing or malformed"
    assert hash1 == ingest_hashes["app-x86_64-v1.tar.gz"], "Curated tarball does not match its ingestion checksum"
    assert hash2 == ingest_hashes["app-arm64-v1.zip"], "Curated zip does not match its ingestion checksum"

    with tarfile.open(file1, "r:gz") as archive:
        assert archive.getmembers(), "Curated tarball is empty or invalid"
    with zipfile.ZipFile(file2, "r") as archive:
        assert archive.testzip() is None, "Curated zip failed its integrity test"
        assert archive.namelist(), "Curated zip is empty"

    assert not os.path.exists(os.path.join(raw_dir, "app-x86_64-v1.tar.gz")), "Valid tarball was not moved from raw_drop"
    assert not os.path.exists(os.path.join(raw_dir, "app-arm64-v1.zip")), "Valid zip was not moved from raw_drop"


def test_script_on_fresh_unpredictable_inputs():
    script = "/home/user/curate.sh"
    assert os.path.isfile(script), "Required Bash script /home/user/curate.sh does not exist"
    assert not os.path.islink(script), "/home/user/curate.sh must be an actual script, not a symbolic link"
    syntax = subprocess.run(["bash", "-n", script], capture_output=True, text=True)
    assert syntax.returncode == 0, f"curate.sh is not valid Bash: {syntax.stderr}"

    raw_dir = "/home/user/raw_drop"
    curated_dir = "/home/user/curated"
    shutil.rmtree(raw_dir, ignore_errors=True)
    shutil.rmtree(curated_dir, ignore_errors=True)
    os.makedirs(raw_dir)

    token = uuid.uuid4().hex
    zip_name = f"alpha-{token}.zip"
    tar_name = f"beta-{token}.tar.gz"
    corrupt_name = f"broken-{token}.tar.gz"
    bitrot_name = f"rot-{token}.tar.gz"
    zip_arch, zip_project = f"arm-{token}", f"client-{token}"
    tar_arch, tar_project = f"x86-{token}", f"server-{token}"

    zip_path = os.path.join(raw_dir, zip_name)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("payload.txt", f"zip payload {token}\n")

    tar_path = os.path.join(raw_dir, tar_name)
    payload = f"tar payload {token}\n".encode()
    with tarfile.open(tar_path, "w:gz") as archive:
        info = tarfile.TarInfo("payload.txt")
        info.size = len(payload)
        archive.addfile(info, io.BytesIO(payload))

    corrupt_path = os.path.join(raw_dir, corrupt_name)
    with open(corrupt_path, "wb") as f:
        f.write(f"not a tar archive {token}".encode())

    bitrot_path = os.path.join(raw_dir, bitrot_name)
    with tarfile.open(bitrot_path, "w:gz") as archive:
        data = f"bitrot payload {token}\n".encode()
        info = tarfile.TarInfo("payload.txt")
        info.size = len(data)
        archive.addfile(info, io.BytesIO(data))

    hashes = {
        zip_name: get_sha256(zip_path),
        tar_name: get_sha256(tar_path),
        corrupt_name: get_sha256(corrupt_path),
        bitrot_name: "0" * 64,
    }
    with open(zip_path, "rb") as f:
        zip_bytes = f.read()
    with open(tar_path, "rb") as f:
        tar_bytes = f.read()

    manifest = [
        {"file": corrupt_name, "project": f"bad-{token}", "arch": tar_arch},
        {"file": tar_name, "project": tar_project, "arch": tar_arch},
        {"file": bitrot_name, "project": f"tools-{token}", "arch": zip_arch},
        {"file": zip_name, "project": zip_project, "arch": zip_arch},
    ]
    with open(os.path.join(raw_dir, "vendor_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f)

    with open(os.path.join(raw_dir, "ingest.log"), "w", encoding="utf-8") as f:
        for index, entry in enumerate(manifest):
            name = entry["file"]
            f.write(f"[START]\nTimestamp: test-{index}-{token}\nFile: {name}\nStatus: SUCCESS\nSHA256: {hashes[name]}\n[END]\n")

    run = subprocess.run(["bash", script], capture_output=True, text=True, timeout=30)
    assert run.returncode == 0, f"curate.sh failed on fresh inputs:\nstdout: {run.stdout}\nstderr: {run.stderr}"

    curated_zip = os.path.join(curated_dir, zip_arch, zip_project, zip_name)
    curated_tar = os.path.join(curated_dir, tar_arch, tar_project, tar_name)
    assert os.path.isfile(curated_zip), "Fresh valid zip was not moved to its manifest destination"
    assert os.path.isfile(curated_tar), "Fresh valid tarball was not moved to its manifest destination"
    with open(curated_zip, "rb") as f:
        assert f.read() == zip_bytes, "Fresh curated zip is not the original verified archive"
    with open(curated_tar, "rb") as f:
        assert f.read() == tar_bytes, "Fresh curated tarball is not the original verified archive"
    assert not os.path.exists(os.path.join(raw_dir, zip_name)), "Fresh valid zip was copied rather than moved"
    assert not os.path.exists(os.path.join(raw_dir, tar_name)), "Fresh valid tarball was copied rather than moved"
    assert os.path.isfile(os.path.join(raw_dir, corrupt_name)), "Corrupt archive should remain excluded in raw_drop"
    assert os.path.isfile(os.path.join(raw_dir, bitrot_name)), "Checksum-mismatched archive should remain excluded in raw_drop"

    found_archives = []
    for root, dirs, files in os.walk(curated_dir):
        for name in files:
            if name != "verified_manifest.csv":
                found_archives.append(os.path.relpath(os.path.join(root, name), curated_dir))
    assert sorted(found_archives) == sorted([
        os.path.relpath(curated_zip, curated_dir),
        os.path.relpath(curated_tar, curated_dir),
    ]), f"Unexpected files were curated: {found_archives}"

    csv_path = os.path.join(curated_dir, "verified_manifest.csv")
    assert os.path.isfile(csv_path), "Fresh run did not create verified_manifest.csv"
    with open(csv_path, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    expected_rows = [
        ["filename", "architecture", "project", "sha256"],
        [zip_name, zip_arch, zip_project, hashes[zip_name]],
        [tar_name, tar_arch, tar_project, hashes[tar_name]],
    ]
    assert rows == expected_rows, f"Fresh-run CSV is incorrect or not filename-sorted: {rows}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
