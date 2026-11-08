#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import stat
import pytest

BASE_DIR = "/home/user/app_audit"

EXPECTED_FILES = {
    "script1.py": (b"print('hello')\n", 0o777),
    "data/script2.py": (b"import os\n", 0o666),
    "secure.py": (b"print('secure')\n", 0o644),
    "network_policy.json": (b'''{
  "firewall": [
    "ALLOW INBOUND TCP 80",
    "DENY INBOUND TCP 22"
  ],
  "csp": [
    "default-src 'self'; script-src 'self'",
    "script-src 'none'; object-src 'none'",
    "default-src https:; img-src 'self'",
    "frame-ancestors 'none'; upgrade-insecure-requests"
  ]
}
''', 0o644),
}

EXPECTED_DIRS = {
    "": 0o777,
    "data": 0o777,
    "config": 0o777,
}


def test_fixture_is_intact():
    expected_entries = set(EXPECTED_DIRS) | set(EXPECTED_FILES)
    actual_entries = {""}

    assert os.path.lexists(BASE_DIR), "Audit fixture directory is missing."
    for root, dirs, files in os.walk(BASE_DIR, followlinks=False):
        rel_root = os.path.relpath(root, BASE_DIR)
        if rel_root == ".":
            rel_root = ""
        for name in dirs + files:
            actual_entries.add(os.path.join(rel_root, name) if rel_root else name)

    assert actual_entries == expected_entries, \
        f"Audit fixture tree was modified. Expected: {expected_entries}; got: {actual_entries}"

    for rel_path, expected_mode in EXPECTED_DIRS.items():
        path = BASE_DIR if not rel_path else os.path.join(BASE_DIR, rel_path)
        st = os.lstat(path)
        assert stat.S_ISDIR(st.st_mode), f"Fixture directory is not a real directory: {path}"
        assert stat.S_IMODE(st.st_mode) == expected_mode, f"Fixture permissions changed: {path}"

    for rel_path, (expected_content, expected_mode) in EXPECTED_FILES.items():
        path = os.path.join(BASE_DIR, rel_path)
        st = os.lstat(path)
        assert stat.S_ISREG(st.st_mode), f"Fixture file is not a regular file: {path}"
        assert stat.S_IMODE(st.st_mode) == expected_mode, f"Fixture permissions changed: {path}"
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"Fixture content changed: {path}"


def test_audit_report_exists():
    assert os.path.isfile("/home/user/audit_report.json"), "Audit report /home/user/audit_report.json does not exist."


def test_audit_report_content():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), "Audit report missing."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Audit report is not valid JSON.")

    assert "vulnerable_files" in report, "Missing 'vulnerable_files' key in report."
    assert "insecure_csp" in report, "Missing 'insecure_csp' key in report."

    # Compute expected vulnerable files and hashes dynamically
    expected_vulnerable_files = {}
    base_dir = "/home/user/app_audit"
    for root, dirs, files in os.walk(base_dir):
        for file in files:
            file_path = os.path.join(root, file)
            # Check if world-writable (others have write permission)
            if os.stat(file_path).st_mode & 0o002:
                with open(file_path, "rb") as f:
                    file_hash = hashlib.sha256(f.read()).hexdigest()
                expected_vulnerable_files[file_path] = file_hash

    # Compute expected insecure CSPs dynamically
    expected_insecure_csps = []
    policy_path = "/home/user/app_audit/network_policy.json"
    if os.path.isfile(policy_path):
        with open(policy_path, "r") as f:
            try:
                policy = json.load(f)
                for csp in policy.get("csp", []):
                    if "default-src" not in csp:
                        expected_insecure_csps.append(csp)
            except json.JSONDecodeError:
                pass

    # Validate vulnerable_files
    assert report["vulnerable_files"] == expected_vulnerable_files, \
        f"vulnerable_files does not match expected.\nExpected: {expected_vulnerable_files}\nGot: {report['vulnerable_files']}"

    # Validate insecure_csp (order-independent)
    assert isinstance(report["insecure_csp"], list), "'insecure_csp' must be a list."
    assert sorted(report["insecure_csp"]) == sorted(expected_insecure_csps), \
        f"insecure_csp does not match expected.\nExpected: {expected_insecure_csps}\nGot: {report['insecure_csp']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
