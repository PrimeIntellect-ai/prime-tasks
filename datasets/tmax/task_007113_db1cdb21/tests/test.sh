#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

import pytest

AUDIT_SCRIPT = "/home/user/audit.sh"
AUDIT_REPORT = "/home/user/audit_report.json"
ARTIFACTS = "/home/user/artifacts"
DAEMON_PATH = os.path.join(ARTIFACTS, "web_server_daemon")
MANIFEST_PATH = os.path.join(ARTIFACTS, "manifest.txt")
ROOT_CA_PATH = os.path.join(ARTIFACTS, "root_ca.pem")
TEMPLATES_PATH = os.path.join(ARTIFACTS, "templates")


def get_expected_rodata_hash():
    """Dynamically compute the expected SHA256 hash of the .rodata section."""
    result = subprocess.run(
        ["objcopy", "-O", "binary", "--only-section=.rodata", DAEMON_PATH, "/dev/stdout"],
        capture_output=True,
        check=True,
    )
    return hashlib.sha256(result.stdout).hexdigest()


def run_audit():
    subprocess.run(["bash", "-n", AUDIT_SCRIPT], check=True, timeout=10)
    subprocess.run(["bash", AUDIT_SCRIPT], check=True, timeout=30)
    assert os.path.isfile(AUDIT_REPORT), f"Audit script did not create {AUDIT_REPORT}."
    with open(AUDIT_REPORT, "r", encoding="utf-8") as f:
        return json.load(f)


def assert_report_shape(report):
    assert set(report) == {"rodata_hash", "hash_match", "cert_valid", "xss_vuln_count"}
    assert isinstance(report["rodata_hash"], str)
    assert type(report["hash_match"]) is bool
    assert type(report["cert_valid"]) is bool
    assert type(report["xss_vuln_count"]) is int


def test_audit_script_exists():
    assert os.path.isfile(AUDIT_SCRIPT), f"Audit script {AUDIT_SCRIPT} is missing."


def test_audit_script_executes_and_generates_report():
    if os.path.exists(AUDIT_REPORT):
        os.remove(AUDIT_REPORT)
    report = run_audit()
    assert_report_shape(report)


def test_audit_report_exists():
    assert os.path.isfile(AUDIT_REPORT), f"Audit report {AUDIT_REPORT} is missing."


def test_audit_report_content():
    with open(AUDIT_REPORT, "r", encoding="utf-8") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {AUDIT_REPORT} does not contain valid JSON.")

    assert_report_shape(report_data)

    # 1. Check rodata_hash
    expected_hash = get_expected_rodata_hash()
    actual_hash = report_data.get("rodata_hash")
    assert actual_hash == expected_hash, f"rodata_hash is incorrect. Expected {expected_hash}, got {actual_hash}."

    # 2. Check hash_match
    hash_match = report_data.get("hash_match")
    assert hash_match is True, f"hash_match should be True, got {hash_match}."

    # 3. Check cert_valid
    cert_valid = report_data.get("cert_valid")
    assert cert_valid is True, f"cert_valid should be True, got {cert_valid}."

    # 4. Check xss_vuln_count
    # Based on the setup, admin.html and profile.html contain 'eval('
    expected_xss_count = 2
    actual_xss_count = report_data.get("xss_vuln_count")
    assert actual_xss_count == expected_xss_count, f"xss_vuln_count is incorrect. Expected {expected_xss_count}, got {actual_xss_count}."


def test_manifest_is_actually_checked():
    original = open(MANIFEST_PATH, "rb").read()
    try:
        expected_hash = get_expected_rodata_hash()
        replacement = "0" * 64
        if replacement == expected_hash:
            replacement = "f" * 64
        with open(MANIFEST_PATH, "w", encoding="ascii") as f:
            f.write(replacement + "\n")

        report = run_audit()
        assert_report_shape(report)
        assert report["rodata_hash"] == expected_hash
        assert report["hash_match"] is False
    finally:
        with open(MANIFEST_PATH, "wb") as f:
            f.write(original)
        run_audit()


def test_template_files_are_actually_scanned():
    backup_parent = tempfile.mkdtemp(prefix="templates-backup-")
    backup = os.path.join(backup_parent, "templates")
    shutil.copytree(TEMPLATES_PATH, backup)
    try:
        shutil.rmtree(TEMPLATES_PATH)
        os.makedirs(TEMPLATES_PATH)
        files = {
            "clean.html": "<html>evaluation only</html>\n",
            "one.html": "<script>eval(first)</script>\n",
            "two.html": "eval(second) and eval(again)\n",
            "three.html": "prefix eval(third) suffix\n",
            "ignored.txt": "eval(not_an_html_file)\n",
        }
        for name, content in files.items():
            with open(os.path.join(TEMPLATES_PATH, name), "w", encoding="utf-8") as f:
                f.write(content)

        expected = sum(
            1
            for path in glob.glob(os.path.join(TEMPLATES_PATH, "*.html"))
            if "eval(" in open(path, "r", encoding="utf-8").read()
        )
        assert expected == 3
        report = run_audit()
        assert_report_shape(report)
        assert report["xss_vuln_count"] == expected
    finally:
        if os.path.exists(TEMPLATES_PATH):
            shutil.rmtree(TEMPLATES_PATH)
        shutil.copytree(backup, TEMPLATES_PATH)
        shutil.rmtree(backup_parent)
        run_audit()


def test_certificate_chain_is_actually_validated():
    original = open(ROOT_CA_PATH, "rb").read()
    try:
        with open(ROOT_CA_PATH, "w", encoding="ascii") as f:
            f.write("not a valid trusted CA certificate\n")
        report = run_audit()
        assert_report_shape(report)
        assert report["cert_valid"] is False
    finally:
        with open(ROOT_CA_PATH, "wb") as f:
            f.write(original)
        run_audit()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
