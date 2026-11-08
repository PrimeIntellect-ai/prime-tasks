#!/bin/bash
set +e
mkdir -p /logs/verifier

# Restore the supplied inputs so changing the world-writable originals cannot
# weaken the checks.
cat > /home/user/config.json <<'EOF'
{
  "allowed_base_dir": "/home/user/extracted",
  "max_total_bytes": 100
}
EOF
cat > /home/user/manifest.json <<'EOF'
[
  {
    "path": "safe_doc1.txt",
    "content": "Hello World!"
  },
  {
    "path": "../../../home/user/hacked.txt",
    "content": "Malicious payload!"
  },
  {
    "path": "subfolder/safe_doc2.txt",
    "content": "Safe content."
  },
  {
    "path": "/etc/shadow",
    "content": "root:x:..."
  },
  {
    "path": "safe_doc3.txt",
    "content": "This file is going to exceed the 100 byte quota limit if we aren't careful, so it should be skipped."
  }
]
EOF

rm -rf /home/user/extracted
mkdir -p /home/user/extracted
rm -f /home/user/extraction_report.csv /tmp/extractor-under-test

status=0
if [ ! -f /home/user/extractor.cpp ] || [ -L /home/user/extractor.cpp ]; then
    echo "extractor.cpp is missing or is not a regular submission file"
    status=1
elif ! g++ -std=c++17 /home/user/extractor.cpp -o /tmp/extractor-under-test -lcrypto; then
    echo "extractor.cpp did not compile"
    status=1
elif ! timeout 30s /tmp/extractor-under-test /home/user/config.json /home/user/manifest.json; then
    echo "extractor failed on the supplied inputs"
    status=1
fi

cat > /tmp/test_final_state.py <<'TEST_EOF'
import os
import json
import hashlib
import csv
import shutil
import subprocess
import time
import pytest

EXE = "/tmp/extractor-under-test"
REPORT = "/home/user/extraction_report.csv"

def get_expected_state():
    config_path = "/home/user/config.json"
    manifest_path = "/home/user/manifest.json"

    with open(config_path, "r") as f:
        config = json.load(f)
    with open(manifest_path, "r") as f:
        manifest = json.load(f)

    allowed_base_dir = config.get("allowed_base_dir", "/home/user/extracted")
    max_total_bytes = config.get("max_total_bytes", 500)

    expected_files = {}
    total_bytes = 0

    for item in manifest:
        path = item.get("path", "")
        content = item.get("content", "")

        # Security rules: skip if contains '..' or starts with '/'
        if ".." in path or path.startswith("/"):
            continue

        content_bytes = content.encode('utf-8')

        # Quota rule: skip this and all subsequent if max_total_bytes is exceeded
        if total_bytes + len(content_bytes) > max_total_bytes:
            break

        expected_files[path] = content_bytes
        total_bytes += len(content_bytes)

    return allowed_base_dir, expected_files

def test_extracted_files():
    allowed_base_dir, expected_files = get_expected_state()

    assert os.path.isdir(allowed_base_dir), f"Directory {allowed_base_dir} does not exist."

    # Check that all expected files exist and have correct content
    for rel_path, expected_content in expected_files.items():
        full_path = os.path.join(allowed_base_dir, rel_path)
        assert os.path.isfile(full_path), f"Expected file missing: {full_path}"

        with open(full_path, "rb") as f:
            actual_content = f.read()
        assert actual_content == expected_content, f"Content mismatch in {full_path}"

def test_no_extra_files():
    allowed_base_dir, expected_files = get_expected_state()

    # Check that NO extra files exist in the allowed_base_dir
    actual_files = []
    for root, _, files in os.walk(allowed_base_dir):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, allowed_base_dir)
            actual_files.append(rel_path)

    for rel_path in actual_files:
        assert rel_path in expected_files, f"Unexpected file found in extracted directory: {rel_path}"

def test_extraction_report():
    _, expected_files = get_expected_state()
    report_path = "/home/user/extraction_report.csv"

    assert os.path.isfile(report_path), f"Extraction report missing at {report_path}"

    expected_csv_rows = {}
    for rel_path, content in expected_files.items():
        sha256_hash = hashlib.sha256(content).hexdigest()
        expected_csv_rows[rel_path] = sha256_hash

    actual_csv_rows = {}
    with open(report_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["filepath", "sha256"], f"Invalid CSV header in {report_path}: {header}"

        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Invalid CSV row format: {row}"
            actual_csv_rows[row[0]] = row[1]

    assert actual_csv_rows == expected_csv_rows, "Extraction report contents do not match expected successfully written files and checksums."

def read_report():
    with open(REPORT, newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["filepath", "sha256"]
    assert all(len(row) == 2 for row in rows[1:])
    return rows[1:]

def test_program_handles_independent_security_and_quota_case():
    base = "/tmp/extractor-dynamic"
    config = "/tmp/extractor-dynamic-config.json"
    manifest = "/tmp/extractor-dynamic-manifest.json"
    absolute_escape = "/tmp/extractor-absolute-escape.txt"
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    for path in (absolute_escape, REPORT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    items = [
        {"path": "nested/good.txt", "content": "abc"},
        {"path": "name..withdots", "content": "bad"},
        {"path": absolute_escape, "content": "escape"},
        {"path": "too-large.txt", "content": "XYZ"},
        {"path": "must-not-run.txt", "content": "q"},
    ]
    with open(config, "w") as f:
        json.dump({"allowed_base_dir": base, "max_total_bytes": 5}, f)
    with open(manifest, "w") as f:
        json.dump(items, f)

    result = subprocess.run([EXE, config, manifest], timeout=30)
    assert result.returncode == 0
    good = os.path.join(base, "nested/good.txt")
    assert os.path.isfile(good)
    assert open(good, "rb").read() == b"abc"
    assert not os.path.exists(os.path.join(base, "name..withdots"))
    assert not os.path.exists(absolute_escape)
    assert not os.path.exists(os.path.join(base, "too-large.txt"))
    assert not os.path.exists(os.path.join(base, "must-not-run.txt"))
    assert read_report() == [["nested/good.txt", hashlib.sha256(b"abc").hexdigest()]]

def test_atomic_temp_write_and_rename_behavior():
    source = open("/home/user/extractor.cpp", encoding="utf-8", errors="ignore").read()
    assert ".tmp" in source, "source does not construct the required .tmp path"
    assert "rename" in source, "source does not use a rename operation"

    base = "/tmp/extractor-atomic"
    config = "/tmp/extractor-atomic-config.json"
    manifest = "/tmp/extractor-atomic-manifest.json"
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)

    destination = os.path.join(base, "large.bin")
    temporary = destination + ".tmp"
    old = b"old-file-must-remain-visible"
    content = "A" * (64 * 1024 * 1024)
    with open(destination, "wb") as f:
        f.write(old)
    with open(config, "w") as f:
        json.dump({"allowed_base_dir": base, "max_total_bytes": len(content) + 1}, f)
    with open(manifest, "w") as f:
        json.dump([{"path": "large.bin", "content": content}], f)

    proc = subprocess.Popen([EXE, config, manifest])
    saw_tmp = False
    invalid_destination_size = None
    deadline = time.monotonic() + 60
    while proc.poll() is None:
        if os.path.exists(temporary):
            saw_tmp = True
        try:
            size = os.path.getsize(destination)
            if size not in (len(old), len(content)):
                invalid_destination_size = size
                break
        except FileNotFoundError:
            invalid_destination_size = -1
            break
        if time.monotonic() > deadline:
            proc.kill()
            pytest.fail("extractor timed out during atomic-write test")

    if invalid_destination_size is not None and proc.poll() is None:
        proc.kill()
        proc.wait()
    else:
        proc.wait(timeout=5)

    assert proc.returncode == 0
    assert invalid_destination_size is None, "destination was exposed in a partial/non-atomic state"
    assert saw_tmp, "required <destination>.tmp file was never observed"
    assert not os.path.exists(temporary), "temporary file remained after successful extraction"
    assert os.path.getsize(destination) == len(content)
    with open(destination, "rb") as f:
        assert hashlib.sha256(f.read()).hexdigest() == hashlib.sha256(content.encode()).hexdigest()
    assert read_report() == [["large.bin", hashlib.sha256(content.encode()).hexdigest()]]
TEST_EOF

if [ "$status" -eq 0 ]; then
    python3 -m pytest /tmp/test_final_state.py -x --tb=short
    status=$?
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
