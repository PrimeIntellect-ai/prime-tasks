#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
from pathlib import Path
from urllib.parse import parse_qsl, quote, urlsplit

import pytest

REPORT = Path("/home/user/audit_report.json")
LOGS = Path("/home/user/auth_logs.txt")
CSP = Path("/home/user/csp.txt")
PROJECT = Path("/home/user/audit_tool")


def test_audit_report_exists_and_valid():
    """Test that the audit report exists, is valid JSON, and contains the correct data."""
    report_path = "/home/user/audit_report.json"
    assert os.path.exists(report_path), f"Audit report missing at {report_path}"
    assert os.path.isfile(report_path), f"{report_path} is not a file"

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Audit report is not valid JSON")

    assert "csp_is_strict" in data, "Missing 'csp_is_strict' in audit report"
    assert data["csp_is_strict"] is True, "'csp_is_strict' should be true based on csp.txt"

    assert "escalation_attempts" in data, "Missing 'escalation_attempts' in audit report"
    attempts = data["escalation_attempts"]
    assert isinstance(attempts, list), "'escalation_attempts' should be a list"
    assert len(attempts) == 2, f"Expected exactly 2 escalation attempts, found {len(attempts)}"

    expected_attempts = [
        {"ip": "10.0.0.5", "decoded_url": "https://evil.com/admin/escalate?user=test"},
        {"ip": "10.0.0.9", "decoded_url": "https://attacker.net/su/root"}
    ]

    assert attempts == expected_attempts, f"Escalation attempts do not match expected output. Got {attempts}"


def derive_expected(log_text, csp_text):
    attempts = []
    for line in log_text.splitlines():
        fields = line.split(maxsplit=4)
        if len(fields) != 5:
            continue
        ip = fields[1]
        request_path = fields[3]
        query = urlsplit(request_path).query
        values = [value for key, value in parse_qsl(query, keep_blank_values=True) if key == "return_url"]
        if not values:
            continue
        decoded = values[0]
        if not (decoded.startswith("http://") or decoded.startswith("https://")):
            continue
        parsed = urlsplit(decoded)
        if parsed.hostname == "internal.corp":
            continue
        if "/admin/" not in parsed.path and "/su/" not in parsed.path:
            continue
        attempts.append({"ip": ip, "decoded_url": decoded})
    return {
        "csp_is_strict": "'strict-dynamic'" in csp_text,
        "escalation_attempts": attempts,
    }


def make_line(index, ip, target, extra_parameter=False):
    encoded = quote(target, safe="")
    if extra_parameter:
        path = f"/login?source=test&return_url={encoded}&after=ignored"
    else:
        path = f"/login?return_url={encoded}"
    return f"2026-09-12T12:{index:02d}:00Z {ip} GET {path} HTTP/1.1"


def run_and_read(log_text, csp_text):
    LOGS.write_text(log_text, encoding="utf-8")
    CSP.write_text(csp_text, encoding="utf-8")
    if REPORT.exists() or REPORT.is_symlink():
        REPORT.unlink()

    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "The Rust project did not compile and run successfully.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert REPORT.is_file(), "Running the Rust program did not create /home/user/audit_report.json"
    try:
        return json.loads(REPORT.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        pytest.fail(f"Program generated invalid JSON: {exc}")


def test_rust_project_executes_and_analyzes_changed_inputs():
    assert PROJECT.is_dir(), "/home/user/audit_tool must be a directory"
    assert (PROJECT / "Cargo.toml").is_file(), "audit_tool/Cargo.toml is missing"
    rust_sources = [p for p in (PROJECT / "src").rglob("*.rs") if p.is_file()]
    assert rust_sources, "audit_tool/src contains no Rust source files"
    assert any(p.read_text(encoding="utf-8", errors="ignore").strip() for p in rust_sources), \
        "Rust source files are empty"

    originals = {}
    for path in (LOGS, CSP, REPORT):
        originals[path] = path.read_bytes() if path.is_file() else None

    nonce = secrets.token_hex(8)
    evil_a = f"redirect-{nonce}.example"
    evil_b = f"host-{nonce}.test"

    scenario_one_lines = [
        make_line(1, "198.51.100.11", f"https://{evil_a}/ordinary/profile?token={nonce}"),
        make_line(2, "198.51.100.12", f"https://{evil_a}/x/admin/change?token={nonce}", True),
        make_line(3, "198.51.100.13", "http://internal.corp/admin/settings"),
        make_line(4, "198.51.100.14", f"http://{evil_b}/su/operator?value=a%20b"),
        make_line(5, "198.51.100.15", "/admin/local-only"),
        f"2026-09-12T12:06:00Z 198.51.100.16 GET /login?other={nonce} HTTP/1.1",
    ]
    scenario_one = "\n".join(scenario_one_lines) + "\n"
    csp_one = "Content-Security-Policy: default-src 'self'; object-src 'none';\n"

    scenario_two_lines = [
        make_line(10, "203.0.113.21", f"https://{evil_b}/admin/{nonce}"),
        make_line(11, "203.0.113.22", f"https://{evil_a}/administrator/{nonce}"),
        make_line(12, "203.0.113.23", f"http://{evil_a}/prefix/su/{nonce}", True),
        make_line(13, "203.0.113.24", "https://internal.corp/su/root"),
    ]
    scenario_two = "\n".join(scenario_two_lines) + "\n"
    csp_two = "Content-Security-Policy: script-src 'self' 'strict-dynamic'; object-src 'none';\n"

    try:
        actual_one = run_and_read(scenario_one, csp_one)
        assert actual_one == derive_expected(scenario_one, csp_one)

        actual_two = run_and_read(scenario_two, csp_two)
        assert actual_two == derive_expected(scenario_two, csp_two)
    finally:
        for path, content in originals.items():
            if content is None:
                if path.exists() or path.is_symlink():
                    path.unlink()
            else:
                path.write_bytes(content)
TEST_EOF

set +e
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
