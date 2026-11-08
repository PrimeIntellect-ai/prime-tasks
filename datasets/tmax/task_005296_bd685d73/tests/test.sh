#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import fcntl
import io
import json
import os
import subprocess
import time
import uuid


def test_01_setup_md_updated():
    setup_md_path = "/home/user/docs/setup.md"
    assert os.path.isfile(setup_md_path), f"File {setup_md_path} is missing"

    with open(setup_md_path, "r") as f:
        content = f.read()

    expected_json = '{\n  "author": "alice",\n  "status": "review"\n}'
    original_content = '# Setup Guide\nThis is the setup guide.\n'

    assert expected_json in content, f"Expected JSON not found in {setup_md_path}"
    assert original_content.strip() in content, f"Original content missing in {setup_md_path}"
    assert content.startswith(expected_json), f"{setup_md_path} does not start with the expected JSON block"
    assert "\n\n# Setup Guide" in content or "\n\n\n# Setup Guide" in content, "Missing blank line before original content"


def test_02_api_md_updated():
    api_md_path = "/home/user/docs/api.md"
    assert os.path.isfile(api_md_path), f"File {api_md_path} is missing"

    with open(api_md_path, "r") as f:
        content = f.read()

    expected_json = '{\n  "author": "bob",\n  "status": "published"\n}'
    original_content = '# API Reference\nList of endpoints.\n'

    assert expected_json in content, f"Expected JSON not found in {api_md_path}"
    assert original_content.strip() in content, f"Original content missing in {api_md_path}"
    assert content.startswith(expected_json), f"{api_md_path} does not start with the expected JSON block"
    assert "\n\n# API Reference" in content or "\n\n\n# API Reference" in content, "Missing blank line before original content"


def test_03_csv_registry():
    csv_file_path = "/home/user/docs/updated_registry.csv"
    assert os.path.isfile(csv_file_path), f"File {csv_file_path} is missing"

    with open(csv_file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_line_1 = "/home/user/docs/setup.md,alice,review"
    expected_line_2 = "/home/user/docs/api.md,bob,published"

    assert expected_line_1 in lines, f"Expected line '{expected_line_1}' not found in CSV"
    assert expected_line_2 in lines, f"Expected line '{expected_line_2}' not found in CSV"


def test_04_go_script_exists_and_uses_flock():
    go_script_path = "/home/user/fix_docs.go"
    assert os.path.isfile(go_script_path), f"Go script {go_script_path} is missing"

    with open(go_script_path, "r") as f:
        content = f.read()

    assert "syscall.Flock" in content, "Go script does not contain 'syscall.Flock'"
    assert "syscall.LOCK_EX" in content, "Go script does not contain 'syscall.LOCK_EX'"
    assert "syscall.LOCK_UN" in content, "Go script does not explicitly unlock the CSV file"


def test_05_execute_script_with_dynamic_stdin_and_locking():
    script = "/home/user/fix_docs.go"
    registry = "/home/user/docs/updated_registry.csv"
    token = uuid.uuid4().hex[:12]
    binary = f"/tmp/fix_docs_{token}"
    paths = [
        f"/home/user/docs/verify_{token}_one.md",
        f"/home/user/docs/verify_{token}_two.md",
    ]
    originals = [
        f"# Dynamic One {token}\nFirst original body.\n",
        f"# Dynamic Two {token}\nSecond original body.\n",
    ]
    metadata = [
        {"author": f"writer_{token}", "status": f"draft_{token}"},
        {"author": f"editor_{token}", "status": f"review_{token}"},
    ]

    records = []
    for path, values in zip(paths, metadata):
        block = json.dumps(values, indent=2)
        records.append(
            f"[ERROR] File: {path}\n"
            "[DETAILS] Missing metadata. Suggested JSON:\n"
            f"{block}\n"
            "[END]\n"
        )
    dynamic_input = f"[INFO] verifier {token}\n" + "[INFO] between records\n".join(records)

    with open(registry, "rb") as f:
        registry_backup = f.read()

    proc = None
    lock_file = None
    lock_held = False
    try:
        for path, original in zip(paths, originals):
            with open(path, "w") as f:
                f.write(original)

        subprocess.run(
            ["go", "build", "-o", binary, script],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )

        lock_file = open(registry, "w+b", buffering=0)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        lock_held = True

        proc = subprocess.Popen(
            [binary],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        proc.stdin.write(dynamic_input)
        proc.stdin.close()
        proc.stdin = None

        time.sleep(1.0)
        assert proc.poll() is None, (
            "Script completed while another process held an exclusive lock on the registry; "
            "it did not honor the required flock"
        )
        with open(registry, "rb") as f:
            assert f.read() == b"", "Script wrote to the registry despite an external exclusive lock"

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_held = False

        return_code = proc.wait(timeout=15)
        stderr = proc.stderr.read()
        assert return_code == 0, f"Compiled script failed with exit code {return_code}: {stderr}"

        for path, original, values in zip(paths, originals, metadata):
            expected = json.dumps(values, indent=2) + "\n\n" + original
            with open(path, "r") as f:
                actual = f.read()
            assert actual == expected, f"Script did not correctly prepend stdin metadata to {path}"

        with open(registry, "r", newline="") as f:
            rows = list(csv.reader(f))
        expected_rows = [
            [paths[0], metadata[0]["author"], metadata[0]["status"]],
            [paths[1], metadata[1]["author"], metadata[1]["status"]],
        ]
        for row in expected_rows:
            assert row in rows, f"Missing dynamically derived CSV row: {row}"
    finally:
        if lock_held and lock_file is not None:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        if lock_file is not None:
            lock_file.close()
        with open(registry, "wb") as f:
            f.write(registry_backup)
        for path in paths:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        try:
            os.remove(binary)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
