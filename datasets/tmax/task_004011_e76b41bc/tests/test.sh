#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import subprocess

import pytest

BUILD_SCRIPTS_DIR = "/home/user/build_scripts"
MANIFEST_PATH = "/home/user/build_scripts/manifest.json"
CHECKSUM_SCRIPT_PATH = "/home/user/ci_checksum.py"
EXPECTED_FILES = ["android_build.py", "ios_build.py", "orchestrator.py"]
EXPECTED_CONTENTS = {
    "android_build.py": b'''def build_apk():
    print("Building Android APK...")
    return True

def get_shared_config():
    return {"version": "1.0.0", "ndk": "21.4.7075529"}
''',
    "ios_build.py": b'''from android_build import get_shared_config

def build_ipa():
    print("Building iOS IPA...")
    return True

def get_ios_config():
    config = get_shared_config()
    config["target"] = "iOS 14.0"
    return config
''',
    "orchestrator.py": b'''import android_build
import ios_build

def run_polyglot_build():
    android_build.build_apk()
    ios_build.build_ipa()

if __name__ == "__main__":
    run_polyglot_build()
''',
}


def calculate_expected_manifest():
    result = {}
    for fname in os.listdir(BUILD_SCRIPTS_DIR):
        if fname.endswith(".py"):
            path = os.path.join(BUILD_SCRIPTS_DIR, fname)
            with open(path, "rb") as f:
                result[fname] = hashlib.sha256(f.read()).hexdigest()
    return result


def test_patch_applied():
    """Verify that the patch was applied exactly and resolved the circular imports."""
    android_build_path = os.path.join(BUILD_SCRIPTS_DIR, "android_build.py")
    ios_build_path = os.path.join(BUILD_SCRIPTS_DIR, "ios_build.py")

    assert os.path.isfile(android_build_path), f"Missing {android_build_path}"
    assert os.path.isfile(ios_build_path), f"Missing {ios_build_path}"

    with open(android_build_path, "r") as f:
        android_content = f.read()
        assert "import ios_build" not in android_content, "Patch was not applied to android_build.py (circular import still present)."

    with open(ios_build_path, "r") as f:
        ios_content = f.read()
        assert "import android_build\n" not in ios_content, "Patch was not applied to ios_build.py (old import still present)."
        assert "from android_build import get_shared_config" in ios_content, "Patch was not applied to ios_build.py (new import missing)."

    for fname, expected in EXPECTED_CONTENTS.items():
        path = os.path.join(BUILD_SCRIPTS_DIR, fname)
        assert os.path.isfile(path), f"Missing {path}"
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"{fname} does not exactly match the correctly patched version."


def test_ci_checksum_script_exists():
    """Verify that the checksum script was created."""
    assert os.path.isfile(CHECKSUM_SCRIPT_PATH), f"Checksum script {CHECKSUM_SCRIPT_PATH} is missing."


def test_ci_checksum_script_generates_manifest_for_dynamic_inputs():
    """Execute the submitted script and verify that it computes, rather than hard-codes, checksums."""
    probe_name = f"checksum_probe_{secrets.token_hex(12)}.py"
    probe_path = os.path.join(BUILD_SCRIPTS_DIR, probe_name)
    probe_data = secrets.token_bytes(97) + b"\n# dynamic checksum probe\n"

    with open(probe_path, "wb") as f:
        f.write(probe_data)
    with open(MANIFEST_PATH, "w") as f:
        json.dump({"sentinel.py": "not-a-checksum"}, f)

    try:
        completed = subprocess.run(
            ["python3", CHECKSUM_SCRIPT_PATH],
            cwd="/tmp",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert completed.returncode == 0, (
            f"Checksum script failed with exit code {completed.returncode}: {completed.stderr}"
        )
        assert os.path.isfile(MANIFEST_PATH), "Checksum script did not create manifest.json."

        with open(MANIFEST_PATH, "r") as f:
            actual_manifest = json.load(f)
        expected_manifest = calculate_expected_manifest()

        assert isinstance(actual_manifest, dict), "Manifest JSON must be a dictionary."
        assert actual_manifest == expected_manifest, "Executed checksum script produced incorrect manifest contents."
        assert actual_manifest[probe_name] == hashlib.sha256(probe_data).hexdigest()
        assert all(isinstance(k, str) and "/" not in k for k in actual_manifest), "Manifest keys must be exact filenames."
        assert all(
            isinstance(v, str) and re.fullmatch(r"[0-9a-f]{64}", v)
            for v in actual_manifest.values()
        ), "Manifest values must be lowercase SHA256 hex digests."
    finally:
        if os.path.exists(probe_path):
            os.remove(probe_path)

    completed = subprocess.run(
        ["python3", CHECKSUM_SCRIPT_PATH],
        cwd="/tmp",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert completed.returncode == 0, f"Checksum script failed while restoring the final manifest: {completed.stderr}"


def test_manifest_exists_and_correct():
    """Verify that manifest.json exists, is valid JSON, and contains the correct checksums."""
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing. Did you run your script?"

    try:
        with open(MANIFEST_PATH, "r") as f:
            actual_manifest = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")

    assert isinstance(actual_manifest, dict), "Manifest JSON must be a dictionary."

    expected_manifest = {}
    for fname in EXPECTED_FILES:
        path = os.path.join(BUILD_SCRIPTS_DIR, fname)
        assert os.path.isfile(path), f"Expected script {path} is missing."
        with open(path, "rb") as f:
            expected_manifest[fname] = hashlib.sha256(f.read()).hexdigest()

    # Also include any other .py files, as required by "all .py files".
    for fname in os.listdir(BUILD_SCRIPTS_DIR):
        if fname.endswith(".py"):
            path = os.path.join(BUILD_SCRIPTS_DIR, fname)
            with open(path, "rb") as f:
                expected_manifest[fname] = hashlib.sha256(f.read()).hexdigest()

    assert actual_manifest == expected_manifest, "Manifest JSON contents do not match the expected SHA256 checksums of the .py files."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
