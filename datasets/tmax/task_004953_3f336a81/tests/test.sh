#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import stat
import subprocess

import pytest

SCRIPT = "/home/user/generate_report.py"
REPORT = "/home/user/audit_report.json"
LOG = "/home/user/server_logs/auth.log"
BACKUP = "/home/user/home_backup"
MARKERS = (b"-----BEGIN OPENSSH PRIVATE KEY-----", b"-----BEGIN RSA PRIVATE KEY-----")


def run_script():
    if os.path.exists(REPORT):
        os.unlink(REPORT)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"generate_report.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(REPORT), f"The report file {REPORT} was not generated."


def load_report():
    with open(REPORT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file audit_report.json does not contain valid JSON.")


def assert_report_shape_and_order(report_data):
    expected_keys = {"compromised_ips", "vulnerable_keys", "vulnerable_ssh_dirs"}
    assert set(report_data.keys()) == expected_keys, f"The JSON report keys do not match the expected keys. Found: {list(report_data.keys())}"
    for key in expected_keys:
        assert isinstance(report_data[key], list), f"{key} must be a list."
        assert report_data[key] == sorted(report_data[key]), f"{key} list is not sorted alphabetically."


def derive_expected():
    counts = {}
    compromised = set()
    failed_re = re.compile(r"Failed publickey for admin from ([0-9]+(?:\.[0-9]+){3})\b")
    accepted_re = re.compile(r"Accepted publickey for admin from ([0-9]+(?:\.[0-9]+){3})\b")
    any_ip_re = re.compile(r"\b(?:from|by) ([0-9]+(?:\.[0-9]+){3})\b")

    with open(LOG, "r", errors="replace") as f:
        for line in f:
            failed = failed_re.search(line)
            accepted = accepted_re.search(line)
            any_ip = any_ip_re.search(line)
            if not any_ip:
                continue
            ip = any_ip.group(1)
            if failed:
                counts[ip] = counts.get(ip, 0) + 1
            elif accepted:
                if counts.get(ip, 0) == 3:
                    compromised.add(ip)
                counts[ip] = 0
            else:
                counts[ip] = 0

    vulnerable_keys = []
    vulnerable_dirs = []
    for root, dirs, files in os.walk(BACKUP):
        for dirname in dirs:
            path = os.path.abspath(os.path.join(root, dirname))
            if dirname == ".ssh" and stat.S_IMODE(os.stat(path).st_mode) & 0o077:
                vulnerable_dirs.append(path)
        for filename in files:
            path = os.path.abspath(os.path.join(root, filename))
            if not os.path.isfile(path):
                continue
            with open(path, "rb") as f:
                content = f.read()
            if any(marker in content for marker in MARKERS):
                if stat.S_IMODE(os.stat(path).st_mode) & 0o077:
                    vulnerable_keys.append(path)

    return {
        "compromised_ips": sorted(compromised),
        "vulnerable_keys": sorted(vulnerable_keys),
        "vulnerable_ssh_dirs": sorted(vulnerable_dirs),
    }


def test_script_and_generated_reports():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."

    # Execute the submitted artifact against the original fixture before checking
    # all of the verifier's original expected values.
    run_script()
    report_data = load_report()
    assert_report_shape_and_order(report_data)

    expected_ips = ["10.0.0.5", "10.1.1.1"]
    actual_ips = report_data.get("compromised_ips", [])
    assert set(actual_ips) == set(expected_ips), f"compromised_ips do not match expected. Expected {expected_ips}, got {actual_ips}."

    expected_vuln_keys = [
        "/home/user/home_backup/alice/.ssh/id_rsa",
        "/home/user/home_backup/eve/keys/id_rsa",
    ]
    actual_vuln_keys = report_data.get("vulnerable_keys", [])
    assert set(actual_vuln_keys) == set(expected_vuln_keys), f"vulnerable_keys do not match expected. Expected {expected_vuln_keys}, got {actual_vuln_keys}."

    expected_vuln_dirs = ["/home/user/home_backup/bob/.ssh"]
    actual_vuln_dirs = report_data.get("vulnerable_ssh_dirs", [])
    assert set(actual_vuln_dirs) == set(expected_vuln_dirs), f"vulnerable_ssh_dirs do not match expected. Expected {expected_vuln_dirs}, got {actual_vuln_dirs}."

    original_log = open(LOG, "rb").read()
    token = secrets.token_hex(8)
    dynamic_root = os.path.join(BACKUP, "verification_" + token)
    octets = secrets.SystemRandom().sample(range(10, 240), 5)
    good1 = f"198.18.1.{octets[0]}"
    good2 = f"198.18.2.{octets[1]}"
    noise = f"198.18.3.{octets[2]}"
    too_many = f"198.18.4.{octets[3]}"
    interrupted = f"198.18.5.{octets[4]}"

    try:
        lines = [
            f"Sep 10 12:00:01 host sshd[1]: Failed publickey for admin from {good1} port 1 ssh2",
            f"Sep 10 12:00:02 host sshd[1]: Failed publickey for admin from {good1} port 1 ssh2",
            f"Sep 10 12:00:03 host sshd[1]: Failed publickey for admin from {good1} port 1 ssh2",
            f"Sep 10 12:00:04 host sshd[1]: Accepted publickey for admin from {good1} port 1 ssh2",
            f"Sep 10 12:01:01 host sshd[2]: Failed publickey for admin from {good2} port 2 ssh2",
            f"Sep 10 12:01:02 host sshd[3]: Connection closed by {noise} port 3",
            f"Sep 10 12:01:03 host sshd[2]: Failed publickey for admin from {good2} port 2 ssh2",
            f"Sep 10 12:01:04 host sshd[3]: Failed publickey for root from {noise} port 3 ssh2",
            f"Sep 10 12:01:05 host sshd[2]: Failed publickey for admin from {good2} port 2 ssh2",
            f"Sep 10 12:01:06 host sshd[2]: Accepted publickey for admin from {good2} port 2 ssh2",
        ]
        for i in range(4):
            lines.append(f"Sep 10 12:02:0{i} host sshd[4]: Failed publickey for admin from {too_many} port 4 ssh2")
        lines.append(f"Sep 10 12:02:05 host sshd[4]: Accepted publickey for admin from {too_many} port 4 ssh2")
        for i in range(3):
            lines.append(f"Sep 10 12:03:0{i} host sshd[5]: Failed publickey for admin from {interrupted} port 5 ssh2")
        lines.extend([
            f"Sep 10 12:03:04 host sshd[5]: Connection closed by {interrupted} port 5",
            f"Sep 10 12:03:05 host sshd[5]: Accepted publickey for admin from {interrupted} port 5 ssh2",
        ])
        with open(LOG, "w") as f:
            f.write("\n".join(lines) + "\n")

        vulnerable_ssh = os.path.join(dynamic_root, "nested", ".ssh")
        secure_ssh = os.path.join(dynamic_root, "other", ".ssh")
        os.makedirs(vulnerable_ssh)
        os.makedirs(secure_ssh)
        os.chmod(vulnerable_ssh, 0o750)
        os.chmod(secure_ssh, 0o700)

        vulnerable_key = os.path.join(vulnerable_ssh, "unusual_name.txt")
        secure_key = os.path.join(secure_ssh, "secure_key")
        non_key = os.path.join(dynamic_root, "broad_but_not_a_key")
        with open(vulnerable_key, "w") as f:
            f.write("prefix data\n-----BEGIN OPENSSH PRIVATE KEY-----\nsuffix data\n")
        with open(secure_key, "w") as f:
            f.write("prefix -----BEGIN RSA PRIVATE KEY----- suffix\n")
        with open(non_key, "w") as f:
            f.write("ordinary public information\n")
        os.chmod(vulnerable_key, 0o640)
        os.chmod(secure_key, 0o600)
        os.chmod(non_key, 0o666)

        expected = derive_expected()
        run_script()
        dynamic_report = load_report()
        assert_report_shape_and_order(dynamic_report)
        assert dynamic_report == expected, f"Report did not reflect dynamically generated logs and files. Expected {expected}, got {dynamic_report}."

        # Change only permission bits and require a fresh report, exercising the
        # permission audit at execution time rather than accepting fixed paths.
        os.chmod(vulnerable_key, 0o600)
        os.chmod(secure_key, 0o604)
        os.chmod(vulnerable_ssh, 0o700)
        os.chmod(secure_ssh, 0o711)
        expected = derive_expected()
        run_script()
        changed_report = load_report()
        assert_report_shape_and_order(changed_report)
        assert changed_report == expected, f"Report did not reflect changed permission bits. Expected {expected}, got {changed_report}."
    finally:
        with open(LOG, "wb") as f:
            f.write(original_log)
        shutil.rmtree(dynamic_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
