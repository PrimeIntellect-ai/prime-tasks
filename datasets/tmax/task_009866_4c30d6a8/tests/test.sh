#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

PROMPT = "Enter capacity threshold (bytes): "


def test_analyzer_cpp_exists():
    assert os.path.isfile("/home/user/analyzer.cpp"), "Missing C++ source file: /home/user/analyzer.cpp"


def test_analyzer_executable_exists():
    assert os.path.isfile("/home/user/analyzer"), "Missing compiled executable: /home/user/analyzer"
    assert os.access("/home/user/analyzer", os.X_OK), "/home/user/analyzer is not executable"
    with open("/home/user/analyzer", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/analyzer is not a compiled ELF executable"


def test_expect_script_exists():
    assert os.path.isfile("/home/user/run_analysis.exp"), "Missing expect script: /home/user/run_analysis.exp"


def test_expect_script_functionality():
    report_path = "/home/user/capacity_report.txt"
    if os.path.exists(report_path):
        os.remove(report_path)

    try:
        subprocess.run(["expect", "/home/user/run_analysis.exp"], check=True, timeout=10)
    except subprocess.CalledProcessError:
        pytest.fail("The expect script /home/user/run_analysis.exp failed to execute successfully.")
    except subprocess.TimeoutExpired:
        pytest.fail("The expect script /home/user/run_analysis.exp timed out.")

    assert os.path.isfile(report_path), f"The expect script did not create {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        "Backend 10.0.0.10 exceeded with 15500 bytes.",
        "Backend 10.0.0.11 exceeded with 20000 bytes.",
        "Backend 10.0.0.12 exceeded with 15500 bytes.",
        "Backend 10.0.0.13 exceeded with 17000 bytes."
    ]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {report_path}, but got {len(content)}. Content: {content}"

    for expected in expected_lines:
        assert expected in content, f"Expected line '{expected}' not found in {report_path}"

    for line in content:
        assert line.startswith("Backend"), f"Found unexpected line in {report_path} that does not start with 'Backend': {line}"


def derive_expected(routes_text, logs_text, threshold):
    routes = {}
    for line in routes_text.strip().splitlines():
        path, ip = line.split()
        routes[path] = ip

    totals = {}
    for line in logs_text.strip().splitlines():
        _timestamp, path, byte_count = line.split()
        if path in routes:
            ip = routes[path]
            totals[ip] = totals.get(ip, 0) + int(byte_count)

    lines = [
        f"Backend {ip} exceeded with {totals[ip]} bytes."
        for ip in sorted(totals)
        if totals[ip] > threshold
    ]
    return PROMPT + "".join(line + "\n" for line in lines)


def run_analyzer(binary, threshold):
    try:
        result = subprocess.run(
            [binary],
            input=f"{threshold}\n",
            text=True,
            capture_output=True,
            timeout=5,
            check=True,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{binary} timed out while waiting for or processing the threshold")
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"{binary} exited with status {exc.returncode}; stderr: {exc.stderr!r}")
    assert result.stderr == "", f"{binary} produced unexpected stderr output: {result.stderr!r}"
    return result.stdout


def test_source_and_executable_parse_aggregate_threshold_and_sort():
    routes_path = "/home/user/proxy_routes.conf"
    logs_path = "/home/user/proxy_access.log"
    with open(routes_path, "rb") as f:
        original_routes = f.read()
    with open(logs_path, "rb") as f:
        original_logs = f.read()

    nonce = secrets.randbelow(8000) + 1000
    threshold = secrets.randbelow(4000) + 11000
    p1 = f"/alpha-{nonce}"
    p2 = f"/alpha-extra-{nonce}"
    p3 = f"/beta-{nonce}"
    p4 = f"/gamma-{nonce}"
    unknown = f"/unrouted-{nonce}"
    ip_exact = f"10.{nonce % 200 + 1}.0.9"
    ip_over = f"10.{nonce % 200 + 1}.0.10"
    ip_aggregate = f"172.{nonce % 200 + 1}.0.20"

    first_part = threshold // 2
    second_part = threshold - first_part
    routes_text = (
        f"{p1} {ip_aggregate}\n"
        f"{p3} {ip_exact}\n"
        f"{p4} {ip_over}\n"
        f"{p2} {ip_aggregate}\n"
    )
    logs_text = (
        f"2026-01-01T00:00:00 {p1} {first_part}\n"
        f"2026-01-01T00:00:01 {p3} {threshold}\n"
        f"2026-01-01T00:00:02 {p4} {threshold + 1}\n"
        f"2026-01-01T00:00:03 {p2} {second_part + 50}\n"
        f"2026-01-01T00:00:04 {unknown} 99999999\n"
    )

    def install_fixture():
        with open(routes_path, "w") as f:
            f.write(routes_text)
        with open(logs_path, "w") as f:
            f.write(logs_text)

    try:
        with tempfile.TemporaryDirectory() as td:
            rebuilt = os.path.join(td, "analyzer")
            try:
                subprocess.run(
                    ["g++", "-std=c++17", "/home/user/analyzer.cpp", "-o", rebuilt],
                    check=True,
                    text=True,
                    capture_output=True,
                    timeout=20,
                )
            except subprocess.TimeoutExpired:
                pytest.fail("analyzer.cpp compilation timed out")
            except subprocess.CalledProcessError as exc:
                pytest.fail(f"analyzer.cpp did not compile with g++ -std=c++17: {exc.stderr}")

            with open(rebuilt, "rb") as f:
                assert f.read(4) == b"\x7fELF", "Compiling analyzer.cpp did not produce an ELF executable"

            for binary in ("/home/user/analyzer", rebuilt):
                for tested_threshold in (0, threshold, threshold + 50):
                    install_fixture()
                    actual = run_analyzer(binary, tested_threshold)
                    expected = derive_expected(routes_text, logs_text, tested_threshold)
                    assert actual == expected, (
                        f"Unexpected output from {binary} at threshold {tested_threshold}. "
                        f"Expected {expected!r}, got {actual!r}"
                    )
    finally:
        with open(routes_path, "wb") as f:
            f.write(original_routes)
        with open(logs_path, "wb") as f:
            f.write(original_logs)


def test_expect_script_really_drives_analyzer_and_filters_report():
    analyzer = "/home/user/analyzer"
    report = "/home/user/capacity_report.txt"
    backup = f"/tmp/analyzer-backup-{os.getpid()}-{secrets.token_hex(6)}"
    marker = secrets.randbelow(180) + 20
    ip1 = f"192.0.2.{marker}"
    ip2 = f"198.51.100.{marker}"
    expected = [
        f"Backend {ip1} exceeded with 16001 bytes.",
        f"Backend {ip2} exceeded with 27002 bytes.",
    ]

    os.replace(analyzer, backup)
    try:
        mock = f'''#!/usr/bin/env python3
import sys
sys.stdout.write("Enter capacity threshold (bytes): ")
sys.stdout.flush()
value = sys.stdin.readline().strip()
if value != "15000":
    sys.exit(7)
print("automation diagnostic that must not enter the report")
print("Backend {ip1} exceeded with 16001 bytes.")
print("Backend {ip2} exceeded with 27002 bytes.")
'''
        with open(analyzer, "w") as f:
            f.write(mock)
        os.chmod(analyzer, 0o755)
        if os.path.exists(report):
            os.remove(report)

        try:
            subprocess.run(["expect", "/home/user/run_analysis.exp"], check=True, timeout=10)
        except subprocess.TimeoutExpired:
            pytest.fail("The expect script timed out while driving a prompt-compatible analyzer")
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"The expect script failed while driving the analyzer mock: {exc}")

        assert os.path.isfile(report), "The expect script did not create capacity_report.txt"
        with open(report, "r") as f:
            lines = f.read().splitlines()
        assert lines == expected, (
            "The expect script must spawn /home/user/analyzer, send exactly 15000 after "
            "the prompt, and save only the Backend lines in order. "
            f"Expected {expected!r}, got {lines!r}"
        )
    finally:
        if os.path.lexists(analyzer):
            os.remove(analyzer)
        os.replace(backup, analyzer)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
