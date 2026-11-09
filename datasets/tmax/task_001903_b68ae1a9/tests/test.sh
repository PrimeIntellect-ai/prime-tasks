#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import stat
import subprocess


def test_app_redacted_log():
    log_path = "/home/user/app_redacted.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."

    expected_lines = [
        "[2023-10-01 10:00:00] IP=10.0.0.5 GET /rotate?PASSWORD=*** HTTP/1.1",
        "[2023-10-01 10:05:00] IP=192.168.1.10 GET /status HTTP/1.1",
        "[2023-10-01 10:10:00] IP=172.16.0.4 POST /rotate?API_KEY=*** HTTP/1.1",
        "[2023-10-01 10:15:00] IP=10.0.0.5 GET /rotate?PASSWORD=*** HTTP/1.1",
        "[2023-10-01 10:20:00] IP=10.1.1.1 POST /login USER=admin HTTP/1.1"
    ]

    with open(log_path, 'r') as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {log_path}, found {len(actual_lines)}"

    for i, expected_line in enumerate(expected_lines):
        assert actual_lines[i] == expected_line, f"Line {i+1} mismatch. Expected: '{expected_line}', Actual: '{actual_lines[i]}'"


def test_block_ips_sh():
    script_path = "/home/user/block_ips.sh"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."

    expected_rules = {
        "iptables -A INPUT -s 10.0.0.5 -j DROP",
        "iptables -A INPUT -s 172.16.0.4 -j DROP"
    }

    with open(script_path, 'r') as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    actual_rules = set(actual_lines)

    assert len(actual_rules) == len(expected_rules), f"Expected {len(expected_rules)} unique rules in {script_path}, found {len(actual_rules)}"
    assert actual_rules == expected_rules, f"Mismatch in expected iptables rules. Expected: {expected_rules}, Actual: {actual_rules}"
    assert len(actual_lines) == len(expected_rules), "Duplicate or extra lines found in block_ips.sh"


def test_go_program_scans_runtime_inputs(tmp_path):
    source = pathlib.Path("/home/user/sec_tool.go")
    assert source.is_file(), f"File {source} does not exist or is not a regular file."
    assert stat.S_ISREG(source.stat().st_mode), f"File {source} is not a regular file."
    assert source.stat().st_size > 0, f"File {source} is empty."

    binary = tmp_path / "sec_tool"
    build = subprocess.run(
        ["go", "build", "-o", str(binary), str(source)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert build.returncode == 0, f"sec_tool.go did not compile:\n{build.stdout}\n{build.stderr}"

    app_log = pathlib.Path("/home/user/app.log")
    redacted_log = pathlib.Path("/home/user/app_redacted.log")
    block_file = pathlib.Path("/home/user/block_ips.sh")

    def run_case(input_lines, expected_lines, expected_rules):
        app_log.write_text("\n".join(input_lines) + "\n")
        redacted_log.unlink(missing_ok=True)
        block_file.unlink(missing_ok=True)

        run = subprocess.run(
            [str(binary)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert run.returncode == 0, f"Compiled sec_tool failed:\n{run.stdout}\n{run.stderr}"
        assert redacted_log.is_file(), "Program did not create /home/user/app_redacted.log"
        assert block_file.is_file(), "Program did not create /home/user/block_ips.sh"
        assert redacted_log.read_text().splitlines() == expected_lines

        actual_rules = [line.strip() for line in block_file.read_text().splitlines() if line.strip()]
        assert len(actual_rules) == len(expected_rules), "Duplicate or extra firewall rules found"
        assert set(actual_rules) == expected_rules

    suffix = secrets.randbelow(200) + 20
    ip1 = f"198.51.100.{suffix}"
    ip2 = f"203.0.113.{suffix}"
    password1 = "Pass" + secrets.token_hex(8)
    password2 = "Again" + secrets.token_hex(7)
    api_key1 = "Key" + secrets.token_hex(9)
    api_key2 = "Token" + secrets.token_hex(6)

    run_case(
        [
            "runtime fixture header: preserve punctuation !@#$%",
            f"[one] IP={ip1} GET /rotate?PASSWORD={password1} HTTP/1.1",
            f"[two]\tIP={ip2} POST /rotate API_KEY={api_key1} end",
            f"[three] IP={ip1} PASSWORD={password2} and API_KEY={api_key2}",
            "[clean] IP=192.0.2.44 GET /status HTTP/1.1",
        ],
        [
            "runtime fixture header: preserve punctuation !@#$%",
            f"[one] IP={ip1} GET /rotate?PASSWORD=*** HTTP/1.1",
            f"[two]\tIP={ip2} POST /rotate API_KEY=*** end",
            f"[three] IP={ip1} PASSWORD=*** and API_KEY=***",
            "[clean] IP=192.0.2.44 GET /status HTTP/1.1",
        ],
        {
            f"iptables -A INPUT -s {ip1} -j DROP",
            f"iptables -A INPUT -s {ip2} -j DROP",
        },
    )

    ip3 = f"192.0.2.{secrets.randbelow(200) + 20}"
    password3 = "Changed" + secrets.token_hex(10)
    run_case(
        [
            "second independent input",
            f"IP={ip3} POST payload PASSWORD={password3}",
            f"IP={ip1} GET /clean",
        ],
        [
            "second independent input",
            f"IP={ip3} POST payload PASSWORD=***",
            f"IP={ip1} GET /clean",
        ],
        {f"iptables -A INPUT -s {ip3} -j DROP"},
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
