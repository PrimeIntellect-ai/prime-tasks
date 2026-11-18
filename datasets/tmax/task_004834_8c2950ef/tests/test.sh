#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import secrets
import string
import subprocess

import pytest

OUTPUT_FILE = "/home/user/processed_logs.jsonl"
INPUT_FILE = "/home/user/raw_server.log"


def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"The output file {OUTPUT_FILE} was not created."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."


def test_output_file_contents():
    with open(OUTPUT_FILE, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 4, f"Expected 4 lines in {OUTPUT_FILE}, found {len(lines)}."

    expected_data = [
        {
            "timestamp": "2023-10-12T14:32:01Z",
            "method": "GET",
            "path": "/api/v1/users",
            "status": 200,
            "bytes": 1024,
            "ip": "192.168.1.XXX",
            "pii_detected": {
                "emails": ["a*****@example.com"],
                "credit_cards": [],
                "ssns": []
            }
        },
        {
            "timestamp": "2023-10-12T14:35:10Z",
            "method": "POST",
            "path": "/api/v1/payments",
            "status": 201,
            "bytes": 512,
            "ip": "10.0.0.XXX",
            "pii_detected": {
                "emails": ["b*****@domain.co.uk"],
                "credit_cards": ["XXXX-XXXX-XXXX-3456"],
                "ssns": []
            }
        },
        {
            "timestamp": "2023-10-13T09:15:00Z",
            "method": "PUT",
            "path": "/secure/vault/data",
            "status": 403,
            "bytes": 0,
            "ip": "172.16.254.XXX",
            "pii_detected": {
                "emails": ["c*****@hackers.org"],
                "credit_cards": [],
                "ssns": ["XXX-XX-7777"]
            }
        },
        {
            "timestamp": "2023-10-14T00:00:01Z",
            "method": "GET",
            "path": "/health_check",
            "status": 200,
            "bytes": 42,
            "ip": "127.0.0.XXX",
            "pii_detected": {
                "emails": [],
                "credit_cards": [],
                "ssns": []
            }
        }
    ]

    for i, line in enumerate(lines):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {OUTPUT_FILE} is not valid JSON.")

        expected = expected_data[i]

        assert parsed.get("timestamp") == expected["timestamp"], f"Line {i+1} timestamp mismatch."
        assert parsed.get("method") == expected["method"], f"Line {i+1} method mismatch."
        assert parsed.get("path") == expected["path"], f"Line {i+1} path mismatch."
        assert parsed.get("status") == expected["status"], f"Line {i+1} status mismatch."
        assert parsed.get("bytes") == expected["bytes"], f"Line {i+1} bytes mismatch."
        assert parsed.get("ip") == expected["ip"], f"Line {i+1} ip mismatch."

        pii = parsed.get("pii_detected", {})
        assert isinstance(pii, dict), f"Line {i+1} pii_detected is not a dictionary."

        assert set(pii.get("emails", [])) == set(expected["pii_detected"]["emails"]), f"Line {i+1} emails mismatch."
        assert set(pii.get("credit_cards", [])) == set(expected["pii_detected"]["credit_cards"]), f"Line {i+1} credit_cards mismatch."
        assert set(pii.get("ssns", [])) == set(expected["pii_detected"]["ssns"]), f"Line {i+1} ssns mismatch."


def _candidate_scripts():
    home = Path("/home/user")
    return sorted(
        p for p in home.rglob("*.py")
        if p.is_file()
        and "__pycache__" not in p.parts
        and not any(part.startswith(".") for part in p.relative_to(home).parts)
    )


def test_python_script_exists():
    scripts = _candidate_scripts()
    assert scripts, "No Python script was created under /home/user."


def _read_and_check_dynamic_output(expected):
    path = Path(OUTPUT_FILE)
    assert path.is_file(), "The executed script did not create processed_logs.jsonl."
    lines = path.read_text().strip().splitlines()
    assert len(lines) == len(expected), f"Expected {len(expected)} generated records, found {len(lines)}."

    for i, (line, wanted) in enumerate(zip(lines, expected), 1):
        try:
            actual = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Generated line {i} is not valid JSON: {exc}")

        for key in ("timestamp", "method", "path", "status", "bytes", "ip"):
            assert actual.get(key) == wanted[key], f"Generated line {i} {key} mismatch."
        assert isinstance(actual.get("status"), int), f"Generated line {i} status is not an integer."
        assert isinstance(actual.get("bytes"), int), f"Generated line {i} bytes is not an integer."

        pii = actual.get("pii_detected")
        assert isinstance(pii, dict), f"Generated line {i} pii_detected is not a dictionary."
        for category in ("emails", "credit_cards", "ssns"):
            assert isinstance(pii.get(category), list), f"Generated line {i} {category} is not a list."
            assert set(pii[category]) == set(wanted["pii_detected"][category]), \
                f"Generated line {i} {category} mismatch."


def test_script_executes_and_processes_fresh_input():
    alphabet = string.ascii_lowercase
    token = ''.join(secrets.choice(alphabet) for _ in range(10))
    local1 = ''.join(secrets.choice(alphabet) for _ in range(8))
    local2 = ''.join(secrets.choice(alphabet) for _ in range(9))
    local3 = ''.join(secrets.choice(alphabet) for _ in range(7))
    domain = ''.join(secrets.choice(alphabet) for _ in range(8)) + ".test"
    card_digits = ''.join(secrets.choice(string.digits) for _ in range(16))
    card = '-'.join(card_digits[i:i+4] for i in range(0, 16, 4))
    ssn_digits = ''.join(secrets.choice(string.digits) for _ in range(9))
    ssn = f"{ssn_digits[:3]}-{ssn_digits[3:5]}-{ssn_digits[5:]}"
    ip_tail = secrets.randbelow(200) + 20
    bytes1 = secrets.randbelow(8000) + 100
    bytes2 = secrets.randbelow(8000) + 100

    raw = (
        f'[07/Jan/2025:03:04:05 +0000] "GET /API/V2/{token.upper()}?email={local1}@{domain} HTTP/1.1" 202 {bytes1} IP: 198.51.100.{ip_tail}\n'
        f'[2025-02-08T11:12:13Z] "POST /Billing/{token.upper()} HTTP/1.1" 201 {bytes2} IP: 203.0.113.77 CC: {card} User: {local2}@mail.{domain}\n'
        f'[09/Mar/2025:14:15:16 +0000] "PUT /Secure/{token.upper()}/Data?mode=test HTTP/1.0" 403 0 IP: 172.20.30.44 SSN: {ssn} email {local3}@{domain}\n'
        f'[2025-04-10T17:18:19Z] "GET /Health/{token.upper()}?full=1 HTTP/1.1" 200 42 IP: 127.10.20.30\n'
    )

    expected = [
        {
            "timestamp": "2025-01-07T03:04:05Z", "method": "GET",
            "path": f"/api/v2/{token}", "status": 202, "bytes": bytes1,
            "ip": "198.51.100.XXX",
            "pii_detected": {"emails": [f"{local1[0]}*****@{domain}"], "credit_cards": [], "ssns": []}
        },
        {
            "timestamp": "2025-02-08T11:12:13Z", "method": "POST",
            "path": f"/billing/{token}", "status": 201, "bytes": bytes2,
            "ip": "203.0.113.XXX",
            "pii_detected": {"emails": [f"{local2[0]}*****@mail.{domain}"], "credit_cards": [f"XXXX-XXXX-XXXX-{card_digits[-4:]}"], "ssns": []}
        },
        {
            "timestamp": "2025-03-09T14:15:16Z", "method": "PUT",
            "path": f"/secure/{token}/data", "status": 403, "bytes": 0,
            "ip": "172.20.30.XXX",
            "pii_detected": {"emails": [f"{local3[0]}*****@{domain}"], "credit_cards": [], "ssns": [f"XXX-XX-{ssn_digits[-4:]}"]}
        },
        {
            "timestamp": "2025-04-10T17:18:19Z", "method": "GET",
            "path": f"/health/{token}", "status": 200, "bytes": 42,
            "ip": "127.10.20.XXX",
            "pii_detected": {"emails": [], "credit_cards": [], "ssns": []}
        }
    ]

    input_path = Path(INPUT_FILE)
    output_path = Path(OUTPUT_FILE)
    original_input = input_path.read_bytes()
    original_output = output_path.read_bytes() if output_path.exists() else None
    failures = []

    try:
        input_path.write_text(raw)
        for script in _candidate_scripts():
            output_path.unlink(missing_ok=True)
            try:
                result = subprocess.run(
                    ["python3", str(script)],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=20,
                )
                assert result.returncode == 0, f"exit code {result.returncode}: {result.stderr[-500:]}"
                _read_and_check_dynamic_output(expected)
                return
            except Exception as exc:
                failures.append(f"{script}: {exc}")

        pytest.fail("No submitted Python script correctly processed fresh input. " + " | ".join(failures))
    finally:
        input_path.write_bytes(original_input)
        if original_output is None:
            output_path.unlink(missing_ok=True)
        else:
            output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
