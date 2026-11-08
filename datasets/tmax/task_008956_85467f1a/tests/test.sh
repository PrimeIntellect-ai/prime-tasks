#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import tarfile
import tomllib
from email.parser import Parser

import pytest

RESULT_JSON_PATH = "/home/user/result.json"
PACKAGE_DIR = "/home/user/my_package"
DIST_DIR = os.path.join(PACKAGE_DIR, "dist")
PYPROJECT_PATH = os.path.join(PACKAGE_DIR, "pyproject.toml")
SCRIPT_PATH = "/home/user/ci_build.sh"
METADATA_PATH = "/home/user/job_metadata.json"
FIXED_URL = "http://ci.local/webhook?token=abc123&job_id=job_9981&region=us-east"


def _clean_dist():
    shutil.rmtree(DIST_DIR, ignore_errors=True)


def _run_script(url):
    completed = subprocess.run(
        ["bash", SCRIPT_PATH, url],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"ci_build.sh failed for {url!r}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def _validate_generated_output(job_id, expected_hash):
    assert os.path.isfile(RESULT_JSON_PATH), "ci_build.sh did not create result.json."
    with open(RESULT_JSON_PATH, "r") as f:
        data = json.load(f)

    assert data.get("job_id") == job_id
    assert data.get("expected_checksum") == expected_hash

    tar_files = glob.glob(os.path.join(DIST_DIR, "*.tar.gz"))
    assert len(tar_files) == 1, "The script must produce one source distribution from a clean dist directory."
    with open(tar_files[0], "rb") as f:
        computed_hash = hashlib.sha256(f.read()).hexdigest()

    assert data.get("actual_checksum") == computed_hash
    assert isinstance(data.get("match"), bool)
    assert data["match"] == (computed_hash == expected_hash)

    # Ensure the artifact is a real source distribution for the requested package,
    # rather than arbitrary bytes with a matching self-reported hash.
    with tarfile.open(tar_files[0], "r:gz") as archive:
        pkg_info_members = [m for m in archive.getmembers() if m.name.endswith("/PKG-INFO")]
        assert pkg_info_members, "Built archive has no PKG-INFO metadata."
        extracted = archive.extractfile(pkg_info_members[0])
        assert extracted is not None
        package_metadata = Parser().parsestr(extracted.read().decode("utf-8", errors="strict"))
        assert package_metadata["Name"] == "my_package"
        assert package_metadata["Version"] == "0.1.0"


def test_ci_build_script_executes_and_handles_runtime_jobs():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing or is not a regular file."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be the repaired script, not a symlink."
    subprocess.run(["bash", "-n", SCRIPT_PATH], check=True, timeout=10)

    with open(SCRIPT_PATH, "r") as f:
        script_content = f.read()
    assert re.search(r"python3\s+-m\s+build\b", script_content), (
        "ci_build.sh must invoke python3 -m build as required."
    )

    with open(METADATA_PATH, "rb") as f:
        original_metadata_bytes = f.read()
    metadata = json.loads(original_metadata_bytes)
    assert isinstance(metadata.get("jobs"), dict)

    cases = []
    for position in ("middle", "first"):
        job_id = "verify_" + secrets.token_hex(8)
        expected_hash = secrets.token_hex(32)
        metadata["jobs"][job_id] = {"expected_checksum": expected_hash}
        if position == "middle":
            url = f"http://ci.local/webhook?token={secrets.token_hex(6)}&job_id={job_id}&region=test"
        else:
            url = f"http://ci.local/webhook?job_id={job_id}&token={secrets.token_hex(6)}&region=test"
        cases.append((job_id, expected_hash, url))

    try:
        with open(METADATA_PATH, "w") as f:
            json.dump(metadata, f)

        for job_id, expected_hash, url in cases:
            _clean_dist()
            if os.path.exists(RESULT_JSON_PATH):
                os.remove(RESULT_JSON_PATH)
            _run_script(url)
            _validate_generated_output(job_id, expected_hash)
    finally:
        with open(METADATA_PATH, "wb") as f:
            f.write(original_metadata_bytes)
        _clean_dist()
        if os.path.exists(RESULT_JSON_PATH):
            os.remove(RESULT_JSON_PATH)
        _run_script(FIXED_URL)


def test_pyproject_toml_fixed():
    """Check if pyproject.toml was fixed with name and version."""
    assert os.path.isfile(PYPROJECT_PATH), f"{PYPROJECT_PATH} is missing."
    with open(PYPROJECT_PATH, "r") as f:
        content = f.read()
    assert "my_package" in content, "pyproject.toml is missing the package name 'my_package'."
    assert "0.1.0" in content, "pyproject.toml is missing the version '0.1.0'."

    with open(PYPROJECT_PATH, "rb") as f:
        parsed = tomllib.load(f)
    assert parsed.get("project", {}).get("name") == "my_package"
    assert parsed.get("project", {}).get("version") == "0.1.0"


def test_package_built():
    """Check if the Python package was successfully built into a source distribution."""
    assert os.path.isdir(DIST_DIR), f"{DIST_DIR} directory is missing. Build may have failed."
    tar_files = glob.glob(os.path.join(DIST_DIR, "*.tar.gz"))
    assert len(tar_files) > 0, "No .tar.gz file found in the dist directory."


def test_result_json_exists_and_valid():
    """Check if result.json exists and contains strictly valid JSON."""
    assert os.path.isfile(RESULT_JSON_PATH), f"{RESULT_JSON_PATH} is missing."
    try:
        with open(RESULT_JSON_PATH, "r") as f:
            json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{RESULT_JSON_PATH} does not contain valid JSON.")


def test_result_json_content():
    """Check if result.json contains the correct values based on the task."""
    with open(RESULT_JSON_PATH, "r") as f:
        data = json.load(f)

    assert "job_id" in data, "result.json is missing 'job_id'."
    assert data["job_id"] == "job_9981", f"Expected job_id to be 'job_9981', got '{data['job_id']}'."

    expected_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    assert "expected_checksum" in data, "result.json is missing 'expected_checksum'."
    assert data["expected_checksum"] == expected_hash, f"Expected expected_checksum to be '{expected_hash}', got '{data['expected_checksum']}'."

    tar_files = glob.glob(os.path.join(DIST_DIR, "*.tar.gz"))
    assert len(tar_files) > 0, "Cannot compute actual checksum because no .tar.gz file exists."

    with open(tar_files[0], "rb") as f:
        file_bytes = f.read()
        computed_hash = hashlib.sha256(file_bytes).hexdigest()

    assert "actual_checksum" in data, "result.json is missing 'actual_checksum'."
    assert data["actual_checksum"] == computed_hash, f"Expected actual_checksum to be '{computed_hash}', got '{data['actual_checksum']}'."

    assert "match" in data, "result.json is missing 'match'."
    assert isinstance(data["match"], bool), "'match' in result.json must be a boolean."
    expected_match = (computed_hash == expected_hash)
    assert data["match"] == expected_match, f"Expected match to be {expected_match}, got {data['match']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
