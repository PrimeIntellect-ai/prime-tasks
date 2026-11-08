#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid

SCRIPT_PATH = "/home/user/check_policy.py"
FLAGGED_PATH = "/home/user/flagged.txt"
METADATA_PATH = "/home/user/metadata.json"
UPLOADS_PATH = "/home/user/uploads"


def run_policy():
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Policy script exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}, stderr: {result.stderr!r}"
    )


def test_check_policy_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_flagged_txt_correctness():
    # Require the submitted script, rather than a prewritten output file, to
    # produce the result for the original fixture.
    if os.path.exists(FLAGGED_PATH):
        os.remove(FLAGGED_PATH)
    run_policy()

    assert os.path.isfile(FLAGGED_PATH), f"The output file {FLAGGED_PATH} does not exist."
    assert os.path.isfile(METADATA_PATH), f"The metadata file {METADATA_PATH} is missing."

    with open(METADATA_PATH, "r") as f:
        metadata = json.load(f)

    expected_flagged = []

    for item in metadata:
        filename = item.get("filename", "")
        original_path = item.get("original_path", "")
        csp_directive = item.get("csp_directive", "")

        flagged = False

        # Rule 1: Path Traversal
        if "../" in original_path:
            flagged = True

        # Rule 2: Binary Analysis
        file_path = os.path.join(UPLOADS_PATH, filename)
        if os.path.isfile(file_path):
            with open(file_path, "rb") as bf:
                content = bf.read()
                if content.startswith(b"\x7fELF") and b"malicious_payload_x86" in content:
                    flagged = True

        # Rule 3: CSP Enforcement
        if csp_directive != "strict-dynamic":
            flagged = True

        if flagged:
            expected_flagged.append(filename)

    expected_flagged.sort()

    with open(FLAGGED_PATH, "r") as f:
        actual_lines = f.read().splitlines()

    actual_flagged = [line.strip() for line in actual_lines if line.strip()]

    assert actual_flagged == expected_flagged, (
        f"The contents of {FLAGGED_PATH} do not match the expected flagged files. "
        f"Expected: {expected_flagged}, Actual: {actual_flagged}"
    )


def test_policy_on_generated_fixture():
    token = uuid.uuid4().hex
    names = {
        "safe": f"a_safe_{token}.bin",
        "traversal": f"b_traversal_{token}.bin",
        "malware": f"c_malware_{token}.bin",
        "bad_csp": f"d_bad_csp_{token}.bin",
        "non_elf": f"e_non_elf_{token}.bin",
        "clean_elf": f"f_clean_elf_{token}.bin",
        "multiple": f"g_multiple_{token}.bin",
    }

    files = {
        names["safe"]: b"ordinary safe data",
        names["traversal"]: b"ordinary data",
        names["malware"]: b"\x7fELFgenerated malicious_payload_x86 data",
        names["bad_csp"]: b"ordinary data",
        names["non_elf"]: b"MZ malicious_payload_x86 but not ELF",
        names["clean_elf"]: b"\x7fELF clean executable data",
        names["multiple"]: b"\x7fELF malicious_payload_x86 combined",
    }
    metadata = [
        {"filename": names["safe"], "original_path": "incoming/safe.bin", "csp_directive": "strict-dynamic"},
        {"filename": names["traversal"], "original_path": "incoming/../../secret", "csp_directive": "strict-dynamic"},
        {"filename": names["malware"], "original_path": "incoming/malware.bin", "csp_directive": "strict-dynamic"},
        {"filename": names["bad_csp"], "original_path": "incoming/csp.bin", "csp_directive": "self"},
        {"filename": names["non_elf"], "original_path": "incoming/nonelf.bin", "csp_directive": "strict-dynamic"},
        {"filename": names["clean_elf"], "original_path": "incoming/cleanelf.bin", "csp_directive": "strict-dynamic"},
        {"filename": names["multiple"], "original_path": "../combined.bin", "csp_directive": "unsafe-inline"},
    ]
    expected = sorted([
        names["traversal"],
        names["malware"],
        names["bad_csp"],
        names["multiple"],
    ])

    with tempfile.TemporaryDirectory() as backup_root:
        backup_uploads = os.path.join(backup_root, "uploads")
        shutil.copytree(UPLOADS_PATH, backup_uploads)
        with open(METADATA_PATH, "rb") as f:
            original_metadata = f.read()
        original_flagged = None
        if os.path.isfile(FLAGGED_PATH):
            with open(FLAGGED_PATH, "rb") as f:
                original_flagged = f.read()

        try:
            shutil.rmtree(UPLOADS_PATH)
            os.makedirs(UPLOADS_PATH)
            for filename, content in files.items():
                with open(os.path.join(UPLOADS_PATH, filename), "wb") as f:
                    f.write(content)
            with open(METADATA_PATH, "w") as f:
                json.dump(metadata, f)

            if os.path.exists(FLAGGED_PATH):
                os.remove(FLAGGED_PATH)
            run_policy()

            assert os.path.isfile(FLAGGED_PATH), (
                f"The script did not create {FLAGGED_PATH} for the generated fixture."
            )
            with open(FLAGGED_PATH, "r") as f:
                actual = f.read().splitlines()
            assert actual == expected, (
                f"Generated-fixture result was incorrect. Expected: {expected}, Actual: {actual}"
            )
        finally:
            shutil.rmtree(UPLOADS_PATH, ignore_errors=True)
            shutil.copytree(backup_uploads, UPLOADS_PATH)
            with open(METADATA_PATH, "wb") as f:
                f.write(original_metadata)
            if original_flagged is None:
                if os.path.exists(FLAGGED_PATH):
                    os.remove(FLAGGED_PATH)
            else:
                with open(FLAGGED_PATH, "wb") as f:
                    f.write(original_flagged)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
