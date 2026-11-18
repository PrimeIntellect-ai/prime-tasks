#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import stat
import subprocess
import zipfile

import pytest

BASE = "/home/user/config_update"
SCRIPT = os.path.join(BASE, "process_patch.py")
EXTRACT = os.path.join(BASE, "safe_extract")
BACKUP_LIST = os.path.join(BASE, "differential_backup.list")


def md5(data):
    return hashlib.md5(data).hexdigest()


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd=BASE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"process_patch.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="module", autouse=True)
def execute_submission_on_original_inputs():
    assert os.path.lexists(SCRIPT), f"Required script {SCRIPT} does not exist."
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} must be a regular Python script."

    shutil.rmtree(EXTRACT, ignore_errors=True)
    if os.path.lexists(BACKUP_LIST):
        os.remove(BACKUP_LIST)
    for path in [os.path.join(BASE, "evil_traversal.conf"), "/absolute/evil.conf"]:
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)

    run_script()


def test_safe_extract_directory_exists_and_contains_correct_files():
    extract_dir = "/home/user/config_update/safe_extract"
    assert os.path.exists(extract_dir), f"Directory {extract_dir} does not exist. Did you extract the files?"
    assert os.path.isdir(extract_dir), f"{extract_dir} is not a directory."

    expected_files = {"service_a.conf", "service_b.conf", "new_service.conf"}
    actual_files = set(os.listdir(extract_dir))

    for ef in expected_files:
        assert ef in actual_files, f"Expected file {ef} is missing from {extract_dir}."

    expected_contents = {
        "service_a.conf": b"port=8080\nenabled=true\n",
        "service_b.conf": b"port=9090\nenabled=false\n",
        "new_service.conf": b"port=7070\n",
    }
    for name, content in expected_contents.items():
        path = os.path.join(extract_dir, name)
        assert os.path.isfile(path), f"{path} is not a regular extracted file."
        with open(path, "rb") as f:
            assert f.read() == content, f"Extracted content for {name} is incorrect."


def test_no_malicious_files_extracted():
    extract_dir = "/home/user/config_update/safe_extract"
    assert os.path.exists(extract_dir), f"Directory {extract_dir} does not exist."

    actual_files = set(os.listdir(extract_dir))
    expected_files = {"service_a.conf", "service_b.conf", "new_service.conf"}

    unexpected_files = actual_files - expected_files
    assert not unexpected_files, f"Found unexpected files in {extract_dir}, which might indicate a Zip Slip vulnerability was not mitigated: {unexpected_files}"

    # Also check that malicious files didn't end up in parent directory
    parent_dir = "/home/user/config_update"
    parent_files = set(os.listdir(parent_dir))
    assert "evil_traversal.conf" not in parent_files, "Found 'evil_traversal.conf' in parent directory. Zip Slip mitigation failed."

    # Check absolute path extraction failure
    assert not os.path.exists("/absolute/evil.conf"), "Found '/absolute/evil.conf'. Zip Slip mitigation failed."


def test_differential_backup_list_correct():
    list_path = "/home/user/config_update/differential_backup.list"
    assert os.path.exists(list_path), f"File {list_path} does not exist. Did you generate the backup list?"
    assert os.path.isfile(list_path), f"{list_path} is not a file."

    with open(list_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/config_update/safe_extract/new_service.conf",
        "/home/user/config_update/safe_extract/service_b.conf"
    ]

    assert lines == expected_lines, f"Contents of {list_path} do not match the expected sorted list of changed/new files. Expected: {expected_lines}, Got: {lines}"


def test_z_script_handles_derived_randomized_inputs_end_to_end():
    token = secrets.token_hex(8)
    unchanged = f"unchanged_{token}.conf"
    changed = f"changed_{token}.conf"
    new = f"new_{token}.conf"

    contents = {
        unchanged: f"stable={secrets.token_hex(12)}\n".encode(),
        changed: f"current={secrets.token_hex(12)}\n".encode(),
        new: f"created={secrets.token_hex(12)}\n".encode(),
    }
    old_changed = f"old={secrets.token_hex(12)}\n".encode()

    parent_escape = os.path.join(BASE, f"escape_{token}.conf")
    absolute_escape = f"/tmp/absolute_escape_{token}.conf"
    sibling_dir = os.path.join(BASE, f"safe_extract_sibling_{token}")
    sibling_escape = os.path.join(sibling_dir, "escape.conf")

    for path in [parent_escape, absolute_escape]:
        if os.path.lexists(path):
            os.remove(path)
    shutil.rmtree(sibling_dir, ignore_errors=True)
    shutil.rmtree(EXTRACT, ignore_errors=True)
    if os.path.lexists(BACKUP_LIST):
        os.remove(BACKUP_LIST)

    with zipfile.ZipFile(os.path.join(BASE, "patch.zip"), "w") as zf:
        for name, content in contents.items():
            zf.writestr(name, content)
        zf.writestr(f"../escape_{token}.conf", b"parent traversal\n")
        zf.writestr(absolute_escape, b"absolute traversal\n")
        zf.writestr(f"../safe_extract_sibling_{token}/escape.conf", b"prefix traversal\n")

    with open(os.path.join(BASE, "system.wal"), "w") as f:
        f.write(f"ENTRY|100|{unchanged}|{md5(contents[unchanged])}\n")
        # The later record is the last known state and deliberately differs.
        f.write(f"ENTRY|100|{changed}|{md5(contents[changed])}\n")
        f.write(f"ENTRY|200|{changed}|{md5(old_changed)}\n")

    run_script()

    assert os.path.isdir(EXTRACT), "The randomized archive was not extracted."
    assert set(os.listdir(EXTRACT)) == set(contents), "Safe extraction produced missing or unexpected top-level entries."
    for name, expected_content in contents.items():
        path = os.path.join(EXTRACT, name)
        assert os.path.isfile(path), f"Expected extracted file is missing: {path}"
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"Incorrect extracted content for {name}."

    assert not os.path.exists(parent_escape), "A ../ traversal member escaped the extraction directory."
    assert not os.path.exists(absolute_escape), "An absolute archive member was extracted."
    assert not os.path.exists(sibling_escape), "A prefix-confusion traversal escaped into a sibling directory."

    assert os.path.isfile(BACKUP_LIST), "The randomized run did not generate differential_backup.list."
    with open(BACKUP_LIST, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    expected = sorted([
        os.path.join(EXTRACT, changed),
        os.path.join(EXTRACT, new),
    ])
    assert actual == expected, f"Expected derived backup list {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
