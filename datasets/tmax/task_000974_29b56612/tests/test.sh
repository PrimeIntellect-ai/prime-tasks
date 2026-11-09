#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import subprocess
import tempfile
import uuid
import pytest

EVIL_DIR = "/app/corpora/evil"
CLEAN_DIR = "/app/corpora/clean"
SCRIPT_PATH = "/home/user/filter.sh"
TEST_DIR = "/tmp/test_eval"


def run_script(target):
    result = subprocess.run([SCRIPT_PATH, target], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def test_filter_script_behavior():
    # 1. Verify script exists and is executable
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

    # 2. Set up the original testing directory and corpus checks
    if os.path.exists(TEST_DIR):
        shutil.rmtree(TEST_DIR)
    os.makedirs(TEST_DIR)

    evil_files = os.listdir(EVIL_DIR)
    clean_files = os.listdir(CLEAN_DIR)

    for f in evil_files:
        shutil.copy2(os.path.join(EVIL_DIR, f), TEST_DIR)
    for f in clean_files:
        shutil.copy2(os.path.join(CLEAN_DIR, f), TEST_DIR)

    # 3. Execute the student's script
    run_script(TEST_DIR)

    # 4. Verify the .quarantine directory exists
    quarantine_dir = os.path.join(TEST_DIR, ".quarantine")
    assert os.path.isdir(quarantine_dir), f"The .quarantine directory was not created in {TEST_DIR}."

    # 5. Check adversarial corpus criteria
    evil_bypassed = []
    for f in evil_files:
        if not os.path.exists(os.path.join(quarantine_dir, f)):
            evil_bypassed.append(f)

    clean_modified = []
    for f in clean_files:
        if not os.path.exists(os.path.join(TEST_DIR, f)) or os.path.exists(os.path.join(quarantine_dir, f)):
            clean_modified.append(f)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_generated_randomized_files_and_nonrecursive_behavior():
    # Use unpredictable paths and filenames so a submission cannot key off the fixtures.
    target = tempfile.mkdtemp(prefix="filter_eval_", dir="/tmp")
    token = uuid.uuid4().hex

    signature_name = f"asset_{token[:10]}.dat"
    hash_name = f"asset_{token[10:20]}.dat"
    clean_name = f"asset_{token[20:30]}.dat"
    near_signature_name = f"asset_{token[2:12]}_near.dat"

    signature_data = b"EVIL_SIGNATURE\n" + os.urandom(47) + b"\n"
    clean_data = b"ordinary generated project data\n" + os.urandom(53)
    near_signature_data = b"EVIL_SIGNATURE_NOT_EXACT\n" + os.urandom(31)

    # Ensure dynamically generated clean inputs do not accidentally meet the hash rule.
    while hashlib.sha256(clean_data).hexdigest().startswith("badc0de"):
        clean_data += b"x"
    while hashlib.sha256(near_signature_data).hexdigest().startswith("badc0de"):
        near_signature_data += b"x"

    with open(os.path.join(target, signature_name), "wb") as f:
        f.write(signature_data)
    with open(os.path.join(target, clean_name), "wb") as f:
        f.write(clean_data)
    with open(os.path.join(target, near_signature_name), "wb") as f:
        f.write(near_signature_data)

    # Materialize the checksum-rule sample under a fresh unpredictable filename and
    # independently derive that it really satisfies the required checksum prefix.
    hash_source = os.path.join(EVIL_DIR, "evil_hash.txt")
    with open(hash_source, "rb") as f:
        hash_data = f.read()
    assert hashlib.sha256(hash_data).hexdigest().startswith("badc0de"), "Invalid checksum test fixture"
    with open(os.path.join(target, hash_name), "wb") as f:
        f.write(hash_data)

    # A qualifying file below a subdirectory must not be processed.
    nested_dir = os.path.join(target, f"nested_{token[-8:]}")
    os.makedirs(nested_dir)
    nested_name = f"nested_asset_{token[:8]}.dat"
    nested_path = os.path.join(nested_dir, nested_name)
    nested_data = b"EVIL_SIGNATURE\nnested file must remain here\n"
    with open(nested_path, "wb") as f:
        f.write(nested_data)

    run_script(target)

    quarantine = os.path.join(target, ".quarantine")
    assert os.path.isdir(quarantine), ".quarantine was not created"

    for name in (signature_name, hash_name):
        assert os.path.isfile(os.path.join(quarantine, name)), f"Compromised generated file was not quarantined: {name}"
        assert not os.path.exists(os.path.join(target, name)), f"Compromised generated file was not moved: {name}"

    expected_clean = {
        clean_name: clean_data,
        near_signature_name: near_signature_data,
    }
    for name, expected_data in expected_clean.items():
        path = os.path.join(target, name)
        assert os.path.isfile(path), f"Clean generated file was removed: {name}"
        assert not os.path.exists(os.path.join(quarantine, name)), f"Clean generated file was quarantined: {name}"
        with open(path, "rb") as f:
            assert f.read() == expected_data, f"Clean generated file was modified: {name}"

    assert os.path.isfile(nested_path), "A file inside a subdirectory was processed"
    with open(nested_path, "rb") as f:
        assert f.read() == nested_data, "A file inside a subdirectory was modified"
    assert not os.path.exists(os.path.join(quarantine, nested_name)), "A nested file was quarantined"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
