#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import sys

try:
    import tomllib
except ImportError:
    import tomli as tomllib

WORKSPACE_DIR = "/home/user/workspace"
API_CLIENT_DIR = os.path.join(WORKSPACE_DIR, "api-client")
PYPROJECT_TOML = os.path.join(API_CLIENT_DIR, "pyproject.toml")
CLIENT_TEST = os.path.join(API_CLIENT_DIR, "test_client.py")
TEST_RESULTS_LOG = os.path.join(WORKSPACE_DIR, "test_results.log")
DATA1_TXT = os.path.join(WORKSPACE_DIR, "data1.txt")
DATA2_TXT = os.path.join(WORKSPACE_DIR, "data2.txt")
UNIQUE_DATA_TXT = os.path.join(WORKSPACE_DIR, "unique_data.txt")
CHECKSUM_TXT = os.path.join(WORKSPACE_DIR, "checksum.txt")


def dependency_name(spec):
    return re.split(r"[<>=!~;\s\[]", spec, maxsplit=1)[0].lower().replace("_", "-")


def test_pyproject_toml_fixed():
    assert os.path.isfile(PYPROJECT_TOML), f"File missing: {PYPROJECT_TOML}"
    with open(PYPROJECT_TOML, "r") as f:
        content = f.read()
    assert "hypotesis" not in content, "The typo 'hypotesis' is still present in pyproject.toml"
    assert "hypothesis" in content, "The correct dependency 'hypothesis' is missing in pyproject.toml"

    with open(PYPROJECT_TOML, "rb") as f:
        config = tomllib.load(f)
    test_deps = config.get("project", {}).get("optional-dependencies", {}).get("test", [])
    names = {dependency_name(item) for item in test_deps if isinstance(item, str)}
    assert "pytest" in names, "pytest is missing from the project's test dependencies"
    assert "hypothesis" in names, "hypothesis is missing from the project's test dependencies"


def test_package_installs_and_property_tests_run():
    assert os.path.isfile(CLIENT_TEST), f"File missing: {CLIENT_TEST}"

    install = subprocess.run(
        [sys.executable, "-m", "pip", "install", "--disable-pip-version-check", "-e", API_CLIENT_DIR + "[test]"],
        cwd=API_CLIENT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
    )
    assert install.returncode == 0, "Package installation with test dependencies failed:\n" + install.stdout

    result = subprocess.run(
        [sys.executable, "-m", "pytest", CLIENT_TEST],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
    )
    assert result.returncode == 0, "Required property tests failed:\n" + result.stdout
    assert re.search(r"\b[1-9]\d* passed\b", result.stdout.lower()), (
        "pytest did not report any passing tests:\n" + result.stdout
    )


def test_test_results_log():
    assert os.path.isfile(TEST_RESULTS_LOG), f"File missing: {TEST_RESULTS_LOG}"
    with open(TEST_RESULTS_LOG, "r") as f:
        content = f.read().lower()
    assert "passed" in content, "test_results.log does not indicate that tests passed"


def test_unique_data_content():
    assert os.path.isfile(DATA1_TXT), f"File missing: {DATA1_TXT}"
    assert os.path.isfile(DATA2_TXT), f"File missing: {DATA2_TXT}"
    assert os.path.isfile(UNIQUE_DATA_TXT), f"File missing: {UNIQUE_DATA_TXT}"

    with open(DATA1_TXT, "r") as f:
        data1_lines = set(line.strip() for line in f if line.strip())
    with open(DATA2_TXT, "r") as f:
        data2_lines = set(line.strip() for line in f if line.strip())

    expected_unique = sorted(list(data2_lines - data1_lines))

    with open(UNIQUE_DATA_TXT, "r") as f:
        actual_unique = [line.strip() for line in f if line.strip()]

    assert actual_unique == expected_unique, f"unique_data.txt content is incorrect. Expected {expected_unique}, got {actual_unique}"


def test_checksum_content():
    assert os.path.isfile(UNIQUE_DATA_TXT), f"File missing: {UNIQUE_DATA_TXT}"
    assert os.path.isfile(CHECKSUM_TXT), f"File missing: {CHECKSUM_TXT}"

    with open(UNIQUE_DATA_TXT, "rb") as f:
        unique_data_bytes = f.read()

    expected_checksum = hashlib.sha256(unique_data_bytes).hexdigest()

    with open(CHECKSUM_TXT, "r") as f:
        actual_checksum = f.read().strip()

    assert actual_checksum == expected_checksum, f"checksum.txt is incorrect. Expected {expected_checksum}, got {actual_checksum}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
