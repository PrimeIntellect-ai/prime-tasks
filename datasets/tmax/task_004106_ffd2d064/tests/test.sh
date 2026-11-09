#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPT = Path("/home/user/generate_report.sh")
REPORT = Path("/home/user/audit_report.txt")
TOOL = Path("/home/user/audit_tool")
RULES = Path("/home/user/fw_rules.txt")


def test_generate_report_script_exists_and_executable():
    script_path = "/home/user/generate_report.sh"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

    with open(script_path, "rb") as f:
        first_line = f.readline(256)
    assert first_line.startswith(b"#!") and b"bash" in first_line.lower(), \
        "generate_report.sh must be an executable Bash script."


def test_generate_report_runs_successfully():
    result = subprocess.run(
        [str(SCRIPT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, (
        f"generate_report.sh exited with status {result.returncode}. "
        f"stderr: {result.stderr.decode('utf-8', errors='replace')}"
    )


def test_audit_report_exists():
    report_path = "/home/user/audit_report.txt"
    assert os.path.exists(report_path), f"The report file {report_path} does not exist."
    assert os.path.isfile(report_path), f"The path {report_path} is not a file."


def test_audit_report_content():
    report_path = "/home/user/audit_report.txt"
    if not os.path.exists(report_path):
        pytest.fail(f"Report file {report_path} is missing.")

    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Check for correct environment variable injection
    assert "Target IP: 10.0.0.1" in content, "The target IP was not correctly set to 10.0.0.1 in the report."

    # Check for redaction of AWS keys
    assert "Active AWS Credential: REDACTED" in content, "The AWS credential in the tool output was not redacted."
    assert "key REDACTED for backup" in content, "The AWS credential in the firewall rules file was not redacted."
    assert "AKIA" not in content, "Found unredacted AWS credentials (AKIA...) in the report."

    # Check for XSS mitigation
    assert "&lt;script&gt;alert('XSS')&lt;/script&gt;" in content, "The XSS payload was not correctly escaped."
    assert "<" not in content, "Found unescaped '<' character in the report."
    assert ">" not in content, "Found unescaped '>' character in the report."


def test_script_invokes_tool_with_required_environment_and_sanitizes_general_output():
    tool_bytes = TOOL.read_bytes()
    tool_mode = stat.S_IMODE(TOOL.stat().st_mode)
    rules_bytes = RULES.read_bytes()
    rules_mode = stat.S_IMODE(RULES.stat().st_mode)

    key_from_tool = "AKIA" + secrets.token_hex(8).upper()
    key_from_rules = "AKIA" + secrets.token_hex(8).upper()
    nonce = secrets.token_hex(12)

    prefix = (
        f"Dynamic probe {nonce}\n"
        f"Target supplied by environment: $FW_TARGET_IP\n"
        f"Credential=[{key_from_tool}]\n"
        f"Markup=<probe id=\"{nonce}\">left > right</probe>\n"
        "Rules follow:\n"
    )
    dynamic_rules = (
        f"ALLOW dynamic-{nonce}\n"
        f"backup credential {key_from_rules}.\n"
        f"DENY <script data-nonce=\"{nonce}\">alert('dynamic')</script>\n"
        "comparison: 2 > 1 and 1 < 2\n"
    )

    with tempfile.TemporaryDirectory(prefix="audit-verifier-") as td:
        td = Path(td)
        prefix_path = td / "prefix.txt"
        env_log = td / "environment.txt"
        args_log = td / "arguments.bin"
        prefix_path.write_text(prefix, encoding="utf-8")

        probe = f"""#!/bin/sh
printf '%s' "${{FW_TARGET_IP-}}" > {shlex.quote(str(env_log))}
printf '%s\\0' "$@" > {shlex.quote(str(args_log))}
cat {shlex.quote(str(prefix_path))}
if [ "$#" -ge 2 ]; then
    cat "$2"
fi
"""

        try:
            TOOL.unlink()
            TOOL.write_text(probe, encoding="utf-8")
            TOOL.chmod(0o755)
            RULES.write_text(dynamic_rules, encoding="utf-8")

            result = subprocess.run(
                [str(SCRIPT)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
                check=False,
            )
            assert result.returncode == 0, (
                f"generate_report.sh failed against dynamic input with status "
                f"{result.returncode}: {result.stderr.decode('utf-8', errors='replace')}"
            )

            assert env_log.exists(), "The script did not execute /home/user/audit_tool."
            assert env_log.read_text(encoding="utf-8") == "10.0.0.1", \
                "FW_TARGET_IP was not set to 10.0.0.1 for the audit_tool process."

            assert args_log.exists(), "No audit_tool argument record was produced."
            raw_args = args_log.read_bytes().split(b"\0")
            args = [a.decode("utf-8") for a in raw_args if a]
            assert args == ["-f", "/home/user/fw_rules.txt"], \
                f"audit_tool was invoked with incorrect arguments: {args!r}"

            assert REPORT.exists() and REPORT.is_file(), \
                "The script did not create /home/user/audit_report.txt."
            actual = REPORT.read_text(encoding="utf-8")

            raw_expected = prefix.replace("$FW_TARGET_IP", "10.0.0.1") + dynamic_rules
            expected = re.sub(r"AKIA[A-Za-z0-9]{16}", "REDACTED", raw_expected)
            expected = expected.replace("<", "&lt;").replace(">", "&gt;")

            assert actual == expected, (
                "The dynamically generated tool and firewall output was not fully "
                "captured, redacted, escaped, and saved as required."
            )
            assert key_from_tool not in actual and key_from_rules not in actual
            assert not re.search(r"AKIA[A-Za-z0-9]{16}", actual), \
                "A dynamically generated AWS-style key remains in the report."
            assert "<" not in actual and ">" not in actual, \
                "A dynamically generated angle bracket remains unescaped."
        finally:
            if TOOL.exists() or TOOL.is_symlink():
                TOOL.unlink()
            TOOL.write_bytes(tool_bytes)
            TOOL.chmod(tool_mode)
            RULES.write_bytes(rules_bytes)
            RULES.chmod(rules_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
