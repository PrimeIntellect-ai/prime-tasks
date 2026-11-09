#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/alert_monitor.sh"
REPORT_PATH = "/home/user/502_report.txt"
FIXED_LOG_PATH = "/home/user/nginx/logs/error.log"


def run_script(*args):
    return subprocess.run(
        [SCRIPT_PATH, *args],
        capture_output=True,
        text=True,
        timeout=10,
    )


def read_report():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} was not created by the script."
    with open(REPORT_PATH, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_nginx_config_fixed():
    conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config {conf_path} is missing."

    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "unix:/home/user/app/backend.sock;" in content, "The Nginx configuration was not updated to point to the correct backend.sock path."
    assert "unix:/home/user/app/wrong.sock;" not in content, "The old wrong.sock path is still present in the Nginx configuration."

    # Validate the server directive in the actual backend upstream block rather
    # than accepting the desired text in a comment or unrelated directive.
    uncommented = re.sub(r"#.*", "", content)
    match = re.search(r"\bupstream\s+backend\s*\{([^{}]*)\}", uncommented, re.DOTALL)
    assert match, "The Nginx configuration has no valid 'upstream backend' block."
    servers = re.findall(r"\bserver\s+([^;]+)\s*;", match.group(1))
    assert servers == ["unix:/home/user/app/backend.sock"], (
        "The backend upstream must contain exactly the directive "
        "'server unix:/home/user/app/backend.sock;'."
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_requires_exactly_one_argument():
    result = run_script()
    assert result.returncode != 0, "Script must reject invocation with no arguments."

    result = run_script(FIXED_LOG_PATH, FIXED_LOG_PATH)
    assert result.returncode != 0, "Script must reject invocation with more than one argument."


def test_script_execution_and_output():
    # Preserve the original fixed-log behavioral test.
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = run_script(FIXED_LOG_PATH)
    assert result.returncode == 0, f"Script failed to execute. Error: {result.stderr}"

    lines = read_report()
    expected_lines = [
        "[2023/11/01 10:16:22] Client: 10.0.0.5 - Upstream: http://unix:/home/user/app/wrong.sock:/api",
        "[2023/11/01 10:18:45] Client: 172.16.0.12 - Upstream: http://unix:/home/user/app/wrong.sock:/login",
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in the report, but found {len(lines)}."
    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Line {i+1} in report does not match expected format.\nExpected: {expected}\nGot: {lines[i]}"


def test_script_parses_runtime_generated_log_and_filters_nonmatches():
    token = secrets.token_hex(6)
    records = [
        ("2026/02/03", "04:05:06", "10.23.45.67", f"http://unix:/tmp/{token}-one.sock:/alpha"),
        ("2025/12/31", "23:59:58", "172.22.9.201", f"http://unix:/srv/{token}-two.sock:/v2/items?id=7"),
        ("2024/07/19", "11:42:33", "192.168.77.14", f"http://unix:/run/{token}-three.sock:/health/check"),
    ]

    generated_lines = []
    expected = []
    for index, (date, time, client, upstream) in enumerate(records, start=1):
        generated_lines.append(
            f'{date} {time} [error] {7000 + index}#0: *{index} connect() failed '
            f'while connecting to upstream, client: {client}, server: generated, '
            f'request: "GET /{token}/{index} HTTP/1.1", upstream: "{upstream}", host: "localhost"'
        )
        expected.append(f"[{date} {time}] Client: {client} - Upstream: {upstream}")

    # Each distractor is missing at least one required marker and must not appear.
    generated_lines.insert(1, f'2026/01/01 01:01:01 [warn] 1#0: while connecting to upstream, client: 1.2.3.4, upstream: "http://ignored/{token}/warn"')
    generated_lines.insert(3, f'2026/01/01 01:01:02 [error] 1#0: while reading response header, client: 2.3.4.5, upstream: "http://ignored/{token}/phase"')
    generated_lines.append(f'2026/01/01 01:01:03 [error] 1#0: while connecting to upstream, remote: 3.4.5.6, upstream: "http://ignored/{token}/client"')
    generated_lines.append("2026/01/01 01:01:04 [info] 1#0: normal operation")

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = os.path.join(temp_dir, f"generated-{token}.log")
        with open(log_path, "w") as f:
            f.write("\n".join(generated_lines) + "\n")

        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)

        result = run_script(log_path)
        assert result.returncode == 0, f"Script failed on generated log. Error: {result.stderr}"
        assert read_report() == expected, "Script did not correctly parse and filter the generated log."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
