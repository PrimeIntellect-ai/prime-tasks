#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import os
import secrets
import shutil
import subprocess

import pytest

SCRIPT_PATH = "/home/user/enforce_policy.py"
AUTH_PATH = "/home/user/auth.log"
RULES_PATH = "/home/user/cwe_rules.json"
REPORT_PATH = "/home/user/threat_report.json"


def compute_f1(pred, truth):
    pred_set = set(pred)
    truth_set = set(truth)
    if not pred_set and not truth_set:
        return 1.0
    if not pred_set or not truth_set:
        return 0.0

    tp = len(pred_set & truth_set)
    fp = len(pred_set - truth_set)
    fn = len(truth_set - pred_set)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0

    if precision + recall == 0:
        return 0.0
    return 2 * (precision * recall) / (precision + recall)


def run_policy():
    assert os.path.isfile(SCRIPT_PATH), f"Policy script is missing at {SCRIPT_PATH}"
    if os.access(SCRIPT_PATH, os.X_OK):
        command = [SCRIPT_PATH]
    else:
        command = ["python3", SCRIPT_PATH]

    result = subprocess.run(
        command,
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"},
    )
    assert result.returncode == 0, (
        f"Policy script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_report():
    assert os.path.isfile(REPORT_PATH), f"Threat report file is missing at {REPORT_PATH}"
    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")
    assert isinstance(report, dict)
    assert isinstance(report.get("malicious_ips", []), list)
    assert isinstance(report.get("weak_keys", []), list)
    return report


def assert_report_f1(report, truth_ips, truth_keys):
    pred_ips = report.get("malicious_ips", [])
    pred_keys = report.get("weak_keys", [])

    f1_ips = compute_f1(pred_ips, truth_ips)
    f1_keys = compute_f1(pred_keys, truth_keys)
    overall_f1 = (f1_ips + f1_keys) / 2

    assert overall_f1 >= 0.95, (
        f"Overall F1 score is {overall_f1:.4f}, which is below the threshold of 0.95. "
        f"(IP F1: {f1_ips:.4f}, Key F1: {f1_keys:.4f})"
    )


def test_fixed_package_is_installed_and_parses_required_formats():
    assert importlib.metadata.version("ssh_log_analyzer") == "1.0.0"

    cases = [
        (
            "Sep 10 host sshd[1]: Accepted publickey for u from 2001:db8:1::9 port 22 ssh2: "
            "ED25519 SHA256:AbC+de/fG0123456789xyz=",
            "2001:db8:1::9",
            "SHA256:AbC+de/fG0123456789xyz=",
        ),
        (
            "Sep 10 host sshd[2]: Failed publickey for u from 198.51.100.77 port 22 ssh2: "
            "ECDSA SHA256:qwertyUIOP+123/abc=",
            "198.51.100.77",
            "SHA256:qwertyUIOP+123/abc=",
        ),
        (
            "Sep 10 host sshd[3]: Accepted publickey for u from 203.0.113.8 port 22 ssh2: "
            "RSA MD5:de:ad:be:ef:00:11:22:33:44:55:66:77:88:99:aa:bb",
            "203.0.113.8",
            "MD5:de:ad:be:ef:00:11:22:33:44:55:66:77:88:99:aa:bb",
        ),
    ]

    code = """
import json, sys
from ssh_log_analyzer import parse_log_line
print(json.dumps([parse_log_line(line) for line in json.loads(sys.stdin.read())]))
"""
    result = subprocess.run(
        ["python3", "-c", code],
        input=json.dumps([case[0] for case in cases]),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd="/tmp",
        env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"},
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    parsed = json.loads(result.stdout)
    assert len(parsed) == len(cases)
    for item, (_, expected_ip, expected_key) in zip(parsed, cases):
        assert isinstance(item, dict)
        assert item.get("ip") == expected_ip
        assert expected_key in item.get("key_fingerprint", "")


def test_policy_generates_reports_from_inputs():
    original_auth = open(AUTH_PATH, "rb").read()
    original_rules = open(RULES_PATH, "rb").read()
    original_report = open(REPORT_PATH, "rb").read() if os.path.exists(REPORT_PATH) else None

    try:
        # Preserve the original verifier's real F1 assertion, but require the script
        # to produce the report rather than accepting a prewritten JSON file.
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        run_policy()
        original_truth_ips = ["10.0.0.5", "192.168.50.2", "2001:db8::ff00:42:8329"]
        original_truth_keys = [
            "SHA256:p2QAMXGrxoQzK+wM6fK+f9c/8M1e3k6H/9l2A1C3E4Q",
            "MD5:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff:00",
        ]
        assert_report_f1(load_report(), original_truth_ips, original_truth_keys)

        token = secrets.token_hex(10)
        weak_sha = f"SHA256:{token}+Q/{secrets.token_hex(6)}="
        md5_bytes = [secrets.token_hex(1) for _ in range(16)]
        weak_md5 = "MD5:" + ":".join(md5_bytes)
        safe_sha = f"SHA256:safe{secrets.token_hex(12)}"

        ip_v4_a = f"198.51.100.{secrets.randbelow(150) + 20}"
        ip_v4_b = f"203.0.113.{secrets.randbelow(150) + 20}"
        ip_v6 = f"2001:db8:{secrets.randbelow(60000) + 1:x}::7"
        safe_ip = f"192.0.2.{secrets.randbelow(150) + 20}"

        dynamic_log = "\n".join([
            f"Feb 02 10:00:00 host sshd[2001]: Failed publickey for alpha from {ip_v4_a} port 41001 ssh2: ED25519 {weak_sha}",
            f"Feb 02 10:00:01 host sshd[2002]: Accepted publickey for beta from {ip_v6} port 41002 ssh2: ECDSA {weak_sha}",
            f"Feb 02 10:00:02 host sshd[2003]: Failed publickey for gamma from {ip_v4_b} port 41003 ssh2: RSA {weak_md5}",
            f"Feb 02 10:00:03 host sshd[2004]: Accepted publickey for delta from {safe_ip} port 41004 ssh2: ED25519 {safe_sha}",
            "Feb 02 10:00:04 host sshd[2005]: Failed password for invalid user from 192.0.2.250 port 41005 ssh2",
            "",
        ])
        with open(AUTH_PATH, "w") as f:
            f.write(dynamic_log)
        with open(RULES_PATH, "w") as f:
            json.dump({"weak_keys": [weak_sha, weak_md5]}, f)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)

        run_policy()
        dynamic_report = load_report()
        assert_report_f1(
            dynamic_report,
            [ip_v4_a, ip_v6, ip_v4_b],
            [weak_sha, weak_md5],
        )
    finally:
        with open(AUTH_PATH, "wb") as f:
            f.write(original_auth)
        with open(RULES_PATH, "wb") as f:
            f.write(original_rules)
        if original_report is None:
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
        else:
            with open(REPORT_PATH, "wb") as f:
                f.write(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
