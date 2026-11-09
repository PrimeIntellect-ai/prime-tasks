#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess

from cryptography.fernet import Fernet

REPORT_PATH = Path("/home/user/report.json")
EVIDENCE_DIR = Path("/home/user/evidence")
CONFIG_PATH = EVIDENCE_DIR / "config.ini"
CHECKSUM_PATH = EVIDENCE_DIR / "checksum.txt"
ENCRYPTED_PATH = EVIDENCE_DIR / "access.log.enc"


def test_report_exists_and_valid():
    report_path = "/home/user/report.json"
    assert os.path.exists(report_path), f"Report file {report_path} was not created."
    assert os.path.isfile(report_path), f"{report_path} is not a valid file."

    try:
        with open(report_path, 'r') as f:
            report_data = json.load(f)
    except json.JSONDecodeError as e:
        assert False, f"Failed to parse {report_path} as JSON: {e}"

    assert "exploits" in report_data, "The JSON report is missing the 'exploits' key."
    assert isinstance(report_data["exploits"], list), "The 'exploits' key must contain a list."

    expected_exploits = [
        {
            "ip": "172.16.0.44",
            "target_url": "http://evil-phishing.com/login"
        },
        {
            "ip": "203.0.113.88",
            "target_url": "https://steal-credentials.org/"
        }
    ]

    # Sort both lists by IP to ensure order doesn't cause a failure
    actual_exploits = sorted(report_data["exploits"], key=lambda x: x.get("ip", ""))
    expected_exploits_sorted = sorted(expected_exploits, key=lambda x: x["ip"])

    assert len(actual_exploits) == len(expected_exploits_sorted), \
        f"Expected {len(expected_exploits_sorted)} exploits, but found {len(actual_exploits)}."

    for actual, expected in zip(actual_exploits, expected_exploits_sorted):
        assert actual.get("ip") == expected["ip"], \
            f"Expected IP {expected['ip']}, but got {actual.get('ip')}."
        assert actual.get("target_url") == expected["target_url"], \
            f"Expected target_url {expected['target_url']}, but got {actual.get('target_url')}."


def _report_matches(expected):
    try:
        with REPORT_PATH.open("r") as f:
            data = json.load(f)
    except (OSError, ValueError, TypeError):
        return False

    exploits = data.get("exploits") if isinstance(data, dict) else None
    if not isinstance(exploits, list) or len(exploits) != len(expected):
        return False

    try:
        actual_pairs = sorted((item.get("ip"), item.get("target_url")) for item in exploits)
    except (AttributeError, TypeError):
        return False
    expected_pairs = sorted((item["ip"], item["target_url"]) for item in expected)
    return actual_pairs == expected_pairs


def _write_evidence(log_data, key, checksum):
    config = configparser.ConfigParser()
    config["security"] = {"log_encryption_key": key.decode("ascii")}
    with CONFIG_PATH.open("w") as f:
        config.write(f)
    CHECKSUM_PATH.write_text(checksum)
    ENCRYPTED_PATH.write_bytes(Fernet(key).encrypt(log_data))


def _run_script(path):
    try:
        return subprocess.run(
            ["python3", str(path)],
            cwd=str(path.parent),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def test_python_analysis_script_executes_dynamic_evidence_and_checks_integrity():
    scripts = sorted(
        p for p in Path("/home/user").rglob("*.py")
        if p.is_file() and not p.is_symlink()
    )
    assert scripts, "No Python analysis script was created under /home/user."

    original = {}
    for path in (CONFIG_PATH, CHECKSUM_PATH, ENCRYPTED_PATH, REPORT_PATH):
        original[path] = path.read_bytes() if path.exists() else None

    marker = secrets.token_hex(8)
    attacker_ip_1 = f"198.51.100.{secrets.randbelow(200) + 1}"
    attacker_ip_2 = f"203.0.113.{secrets.randbelow(200) + 1}"
    url_1 = f"http://phish-{marker}.example/login"
    url_2 = f"https://steal-{marker}.example/collect"
    expected = [
        {"ip": attacker_ip_1, "target_url": url_1},
        {"ip": attacker_ip_2, "target_url": url_2},
    ]

    log_text = (
        '192.0.2.10 - - [11/Sep/2026:10:00:00 -0000] "GET / HTTP/1.1" 200 512\n'
        '10.0.0.5 - - [11/Sep/2026:10:01:00 -0000] "GET /login?redirect=/dashboard HTTP/1.1" 302 123\n'
        f'{attacker_ip_1} - - [11/Sep/2026:10:02:00 -0000] "GET /login?redirect={url_1} HTTP/1.1" 302 123\n'
        '192.0.2.11 - - [11/Sep/2026:10:03:00 -0000] "POST /login?redirect=http://post.example/ HTTP/1.1" 302 123\n'
        f'{attacker_ip_2} - - [11/Sep/2026:10:04:00 -0000] "GET /login?redirect={url_2} HTTP/1.1" 302 123\n'
        '192.0.2.12 - - [11/Sep/2026:10:05:00 -0000] "GET /login?redirect=http://failed.example/ HTTP/1.1" 404 123\n'
        '127.0.0.1 - - [11/Sep/2026:10:06:00 -0000] "GET /login?redirect=/profile HTTP/1.1" 302 123\n'
    )
    log_data = log_text.encode("utf-8")
    checksum = hashlib.sha256(log_data).hexdigest()
    key = Fernet.generate_key()

    successful_script = None
    diagnostics = []
    try:
        for script in scripts:
            _write_evidence(log_data, key, checksum)
            REPORT_PATH.unlink(missing_ok=True)
            valid_run = _run_script(script)
            if valid_run is None or valid_run.returncode != 0 or not _report_matches(expected):
                diagnostics.append(f"{script}: failed valid encrypted evidence run")
                continue

            # The same script must reject data whose supplied SHA256 checksum is wrong.
            _write_evidence(log_data, key, "0" * 64)
            REPORT_PATH.unlink(missing_ok=True)
            _run_script(script)
            if _report_matches(expected):
                diagnostics.append(f"{script}: produced the exploit report despite a bad checksum")
                continue

            successful_script = script
            break

        assert successful_script is not None, (
            "No Python script decrypted fresh Fernet evidence, generated the derived report, "
            "and rejected an integrity-check failure. " + "; ".join(diagnostics)
        )
    finally:
        for path, content in original.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
