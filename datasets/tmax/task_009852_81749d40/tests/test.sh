#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import pytest

SOURCE = "/home/user/analyzer.cpp"
BINARY = "/tmp/analyzer_verifier"
LOG = "/home/user/proxy_logs.txt"
REPORT = "/home/user/forensic_report.txt"


def log_line(ip, timestamp, method, path, status, headers, cookies):
    headers_json = json.dumps(headers, separators=(", ", ": ")).replace('"', '\\"')
    cookies_json = json.dumps(cookies, separators=(", ", ": ")).replace('"', '\\"')
    return (
        f'{ip} - [{timestamp}] "{method} {path} HTTP/1.1" {status} '
        f'"{headers_json}" "{cookies_json}"'
    )


def write_log(lines):
    with open(LOG, "w") as f:
        f.write("\n".join(lines) + "\n")


def run_analyzer():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Analyzer exited with status {result.returncode}. stderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), f"The file {REPORT} was not created by the analyzer."
    with open(REPORT, "r") as f:
        return f.read().strip()


@pytest.fixture(scope="session", autouse=True)
def compile_analyzer():
    assert os.path.lexists(SOURCE), f"The required source file {SOURCE} does not exist."
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"{SOURCE} must be a regular C++ source file."
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"Failed to compile {SOURCE}:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)


def test_analyzer_parses_and_correlates_runtime_log():
    token = secrets.token_hex(5)
    attacker_ip = f"198.51.100.{secrets.randbelow(200) + 1}"
    target_path = f"/admin/runtime-{token}"
    timestamp = "12/Sep/2026:09:30:00 +0000"

    lines = [
        log_line("10.20.30.40", timestamp, "GET", "/index.html", 200,
                 {"User-Agent": "Browser"}, {"session_role": "guest"}),
        log_line(attacker_ip, timestamp, "GET", target_path, 403,
                 {"User-Agent": "runtime-client"}, {"session_role": "user"}),
        log_line(attacker_ip, timestamp, "GET", target_path, 403,
                 {"User-Agent": "runtime-client", "X-Internal-IP": "127.0.0.1"},
                 {"session_role": "user"}),
        log_line("203.0.113.77", timestamp, "GET", "/admin/decoy", 200,
                 {"User-Agent": "Browser", "X-Internal-IP": "127.0.0.1"},
                 {"session_role": "admin"}),
        log_line(attacker_ip, timestamp, "GET", target_path, 200,
                 {"User-Agent": "runtime-client", "X-Internal-IP": "127.0.0.1"},
                 {"session_role": "admin"}),
    ]
    write_log(lines)

    expected = (
        f"Attacker IP: {attacker_ip}\n"
        f"Target Path: {target_path}\n"
        "Bypass Header: X-Internal-IP: 127.0.0.1\n"
        "Forged Cookie: session_role=admin"
    )
    assert run_analyzer() == expected


def test_forensic_report_exists_and_correct():
    original_lines = [
        log_line("10.0.0.5", "10/Oct/2023:13:55:36 +0000", "GET", "/index.html", 200,
                 {"User-Agent": "Mozilla"}, {"session_role": "guest"}),
        log_line("192.168.1.50", "10/Oct/2023:14:01:12 +0000", "GET", "/admin/secrets", 403,
                 {"User-Agent": "curl/7.68.0"}, {"session_role": "user"}),
        log_line("192.168.1.50", "10/Oct/2023:14:02:05 +0000", "GET", "/admin/secrets", 403,
                 {"User-Agent": "curl/7.68.0", "X-Internal-IP": "127.0.0.1"},
                 {"session_role": "user"}),
        log_line("192.168.1.50", "10/Oct/2023:14:05:10 +0000", "GET", "/admin/secrets", 200,
                 {"User-Agent": "curl/7.68.0", "X-Internal-IP": "127.0.0.1"},
                 {"session_role": "admin"}),
        log_line("172.16.0.10", "10/Oct/2023:14:10:00 +0000", "GET", "/admin/dashboard", 200,
                 {"User-Agent": "Chrome", "X-Internal-IP": "127.0.0.1"},
                 {"session_role": "admin"}),
    ]
    write_log(original_lines)
    run_analyzer()

    report_path = "/home/user/forensic_report.txt"
    assert os.path.isfile(report_path), f"The file {report_path} was not created."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "Attacker IP: 192.168.1.50\n"
        "Target Path: /admin/secrets\n"
        "Bypass Header: X-Internal-IP: 127.0.0.1\n"
        "Forged Cookie: session_role=admin"
    )

    assert content == expected_content, f"The content of {report_path} does not match the expected output. Got:\n{content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
