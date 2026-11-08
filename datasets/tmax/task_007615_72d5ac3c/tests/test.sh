#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
import uuid

import pytest

PROJECT = "/home/user/traffic_dashboard"
SOURCE = os.path.join(PROJECT, "src/main.rs")
REPORT = "/home/user/report.html"
BINARY = os.path.join(PROJECT, "target/debug/traffic_dashboard")

CSP_PATTERN1 = re.compile(r'<meta\s+http-equiv=["\']Content-Security-Policy["\']\s+content=["\']default-src\s+\'self\';["\']\s*/?>', re.IGNORECASE)
CSP_PATTERN2 = re.compile(r'<meta\s+content=["\']default-src\s+\'self\';["\']\s+http-equiv=["\']Content-Security-Policy["\']\s*/?>', re.IGNORECASE)


def has_required_csp(content):
    return bool(CSP_PATTERN1.search(content) or CSP_PATTERN2.search(content))


def html_escape_required(value):
    return (value.replace("&", "&amp;")
                 .replace("<", "&lt;")
                 .replace(">", "&gt;")
                 .replace('"', "&quot;")
                 .replace("'", "&#x27;"))


def run_with_log(search_term, log_content):
    with tempfile.TemporaryDirectory() as workdir:
        with open(os.path.join(workdir, "traffic.log"), "w", encoding="utf-8") as f:
            f.write(log_content)
        result = subprocess.run(
            [BINARY, search_term],
            cwd=workdir,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr
        return result.stdout


def test_audit_report():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"Audit report not found at {report_path}"

    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "CWE-78" in content, "CWE-78 (OS Command Injection) is missing from the audit report."
    assert "CWE-79" in content, "CWE-79 (Cross-Site Scripting) is missing from the audit report."

    lines = content.splitlines()
    assert len(lines) == 2, "The audit report must contain exactly one line per vulnerability."
    assert sorted(lines) == ["CWE-78", "CWE-79"], "Each audit line must consist solely of the correct CWE ID."


def test_source_code_fixed_command_injection():
    assert os.path.isfile(SOURCE), f"Source file not found at {SOURCE}"

    with open(SOURCE, "r", encoding="utf-8") as f:
        content = f.read()

    assert not re.search(r'Command::new\(\s*"sh"\s*\)', content), \
        'Source code still contains Command::new("sh"), indicating the command injection vulnerability is not properly fixed.'


def test_project_builds_real_executable():
    result = subprocess.run(
        ["cargo", "build"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"cargo build failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(BINARY), "cargo build did not produce the required binary."
    assert os.stat(BINARY).st_mode & stat.S_IXUSR, "Built artifact is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Built artifact is not a native executable."


def test_report_html_csp():
    assert os.path.isfile(REPORT), f"Generated report not found at {REPORT}"

    with open(REPORT, "r", encoding="utf-8") as f:
        content = f.read()

    assert has_required_csp(content), "The generated HTML report does not contain the required Content-Security-Policy meta tag."


def test_report_html_xss_escaped():
    assert os.path.isfile(REPORT), f"Generated report not found at {REPORT}"

    with open(REPORT, "r", encoding="utf-8") as f:
        content = f.read()

    assert "<script>alert(1)</script>" not in content, "The generated HTML report contains unescaped malicious HTML tags (XSS vulnerability is still present)."
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in content, "The malicious payload was not properly HTML-escaped in the generated report."


def test_saved_report_was_generated_by_built_program():
    result = subprocess.run(
        [BINARY, "admin"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    with open(REPORT, "r", encoding="utf-8") as f:
        saved = f.read()
    assert saved == result.stdout, "report.html is not the output of the built program run with search term admin."


def test_runtime_filtering_csp_and_complete_html_escaping():
    token = uuid.uuid4().hex
    payload = f'<script data-id="{token}">alert(\'{token}\' & "quoted")</script>'
    ignored = f"ignored-{uuid.uuid4().hex}"
    log = (
        f"10.0.0.1 - admin request User-Agent: {payload}\n"
        f"10.0.0.2 - guest request User-Agent: {ignored}\n"
    )

    output = run_with_log("admin", log)
    escaped = html_escape_required(payload)

    assert has_required_csp(output), "Runtime output is missing the required exact CSP meta tag."
    assert payload not in output, "A User-Agent payload was emitted without HTML escaping."
    assert escaped in output, "Runtime output did not escape <, >, &, double quotes, and single quotes as specified."
    assert ignored not in output, "The program did not filter the traffic log by the supplied search term."


def test_runtime_search_term_cannot_execute_shell_commands():
    token = uuid.uuid4().hex
    marker = f"/tmp/traffic_dashboard_injection_{token}"
    search = f"needle_{token}'; touch {marker}; #"
    ua = f"safe-agent-{token}"
    log = f"request {search} User-Agent: {ua}\n"

    if os.path.exists(marker):
        os.unlink(marker)
    output = run_with_log(search, log)

    assert not os.path.exists(marker), "The search term was interpreted by a shell and executed a command."
    assert ua in output, "The search term was not passed safely as a literal search argument."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
