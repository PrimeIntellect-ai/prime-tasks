#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import re
import secrets
import subprocess
import sys

import pytest
from cryptography.fernet import Fernet

SCRIPT_PATH = "/home/user/redact_audit.py"
RAW_PATH = "/home/user/raw_audit.log"
KEY_PATH = "/home/user/fernet.key"
SAFE_PATH = "/home/user/safe_audit.log"
REPORT_PATH = "/home/user/bandit_report.json"


def test_safe_audit_log_exists():
    assert os.path.exists(SAFE_PATH), f"{SAFE_PATH} does not exist"
    assert os.path.isfile(SAFE_PATH), f"{SAFE_PATH} is not a file"


def test_script_exists_and_processes_derived_input():
    assert os.path.exists(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"

    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()
    with open(KEY_PATH, "rb") as f:
        original_key = f.read()

    card1 = "".join(secrets.choice("0123456789") for _ in range(16))
    card2 = "".join(secrets.choice("0123456789") for _ in range(16))
    while card2 == card1:
        card2 = "".join(secrets.choice("0123456789") for _ in range(16))

    embedded = "2468135790246813"
    seventeen_digits = "13579246801357924"
    synthetic_raw = (
        f"Synthetic payment: {card1}.\n"
        f"Do not alter x{embedded}y or {seventeen_digits}.\n"
        f"Synthetic refund for card [{card2}] completed.\n"
    )
    synthetic_key = Fernet.generate_key()
    synthetic_fernet = Fernet(synthetic_key)

    synthetic_run = None
    restore_run = None
    try:
        with open(RAW_PATH, "w", encoding="utf-8") as f:
            f.write(synthetic_raw)
        with open(KEY_PATH, "wb") as f:
            f.write(synthetic_key)
        if os.path.lexists(SAFE_PATH):
            os.remove(SAFE_PATH)

        synthetic_run = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert synthetic_run.returncode == 0, (
            f"redact_audit.py failed on a derived input:\n{synthetic_run.stderr}"
        )
        assert os.path.isfile(SAFE_PATH), "The script did not create safe_audit.log"

        with open(SAFE_PATH, "r", encoding="utf-8") as f:
            safe_content = f.read()

        tokens = re.findall(r"ENC\(([^)]+)\)", safe_content)
        expected_cards = re.findall(r"\b\d{16}\b", synthetic_raw)
        assert len(tokens) == len(expected_cards) == 2

        decrypted = []
        for token in tokens:
            try:
                decrypted.append(
                    synthetic_fernet.decrypt(token.encode("utf-8")).decode("utf-8")
                )
            except Exception as exc:
                pytest.fail(f"The script produced an invalid Fernet token: {exc}")

        assert decrypted == expected_cards, "The derived credit card values were not encrypted in order"
        token_iter = iter(tokens)
        restored = re.sub(
            r"ENC\(([^)]+)\)",
            lambda match: synthetic_fernet.decrypt(next(token_iter).encode("utf-8")).decode("utf-8"),
            safe_content,
        )
        assert restored == synthetic_raw, "The script altered text other than the matched card numbers"
        assert f"x{embedded}y" in safe_content
        assert seventeen_digits in safe_content
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        with open(KEY_PATH, "wb") as f:
            f.write(original_key)
        restore_run = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )

    assert restore_run.returncode == 0, (
        f"redact_audit.py failed on the required input:\n{restore_run.stderr}"
    )


def test_bandit_report_exists_and_valid():
    assert os.path.exists(REPORT_PATH), f"{REPORT_PATH} does not exist"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file"

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not valid JSON")

    assert "results" in data or "metrics" in data, "JSON does not look like a bandit report"
    assert isinstance(data.get("results"), list), "Bandit report results must be a list"
    assert isinstance(data.get("metrics"), dict), "Bandit report metrics must be an object"
    assert isinstance(data.get("errors"), list), "Bandit report errors must be a list"
    assert isinstance(data.get("generated_at"), str), "Bandit report is missing generated_at"
    try:
        datetime.datetime.fromisoformat(data["generated_at"].replace("Z", "+00:00"))
    except ValueError:
        pytest.fail("Bandit report generated_at is not a valid timestamp")

    fresh_run = subprocess.run(
        ["bandit", "-q", "-f", "json", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert fresh_run.returncode in (0, 1), f"Bandit could not scan the script: {fresh_run.stderr}"
    try:
        fresh = json.loads(fresh_run.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Bandit did not produce valid JSON during verification: {fresh_run.stderr}")

    def script_metric(report):
        matches = [
            value for name, value in report["metrics"].items()
            if name != "_totals" and os.path.basename(name) == os.path.basename(SCRIPT_PATH)
        ]
        assert len(matches) == 1, "Bandit report does not contain metrics for redact_audit.py"
        return matches[0]

    def script_results(report):
        return [
            result for result in report["results"]
            if os.path.basename(result.get("filename", "")) == os.path.basename(SCRIPT_PATH)
        ]

    assert script_metric(data) == script_metric(fresh), (
        "Reported Bandit metrics do not match an actual scan of redact_audit.py"
    )
    assert script_results(data) == script_results(fresh), (
        "Reported Bandit findings do not match an actual scan of redact_audit.py"
    )


def test_safe_audit_log_content():
    with open(KEY_PATH, "rb") as f:
        key = f.read().strip()
    fernet = Fernet(key)

    assert os.path.exists(SAFE_PATH), "safe_audit.log is missing"
    with open(SAFE_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    tokens = re.findall(r"ENC\(([^)]+)\)", content)
    assert len(tokens) == 2, f"Expected exactly 2 encrypted tokens in the log, found {len(tokens)}"

    decrypted_values = []
    for token in tokens:
        try:
            decrypted_values.append(fernet.decrypt(token.encode("utf-8")).decode("utf-8"))
        except Exception as exc:
            pytest.fail(f"Failed to decrypt token '{token[:10]}...': {exc}")

    assert "1234567812345678" in decrypted_values, "First credit card number was not encrypted properly"
    assert "9876543210987654" in decrypted_values, "Second credit card number was not encrypted properly"

    with open(RAW_PATH, "r", encoding="utf-8") as f:
        raw_content = f.read()

    restored_content = content
    for token, decrypted in zip(tokens, decrypted_values):
        restored_content = restored_content.replace(f"ENC({token})", decrypted)

    assert restored_content == raw_content, "The rest of the log lines do not match the original format"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
