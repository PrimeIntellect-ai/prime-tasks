#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

HOME = Path("/home/user")
SOURCE = HOME / "sec_audit.c"
EXECUTABLE = HOME / "sec_audit"
REPORT = HOME / "audit_report.txt"

BASELINE_CONFIG = """# SSH config
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
"""

BASELINE_LOG = """Jan 10 10:00:01 server sshd[1234]: Failed password for root from 10.9.8.7 port 22 ssh2
Jan 10 10:05:01 server sshd[1235]: Failed password for admin from 10.9.8.7 port 22 ssh2
Jan 10 10:10:01 server sshd[1236]: Failed password for invalid user test from 172.16.5.5 port 22 ssh2
Jan 10 10:15:01 server sshd[1237]: Accepted publickey for user from 192.168.1.1 port 22 ssh2
Jan 10 10:20:01 server sshd[1238]: Failed password for root from 10.9.8.7 port 22 ssh2
Jan 10 10:25:01 server sshd[1239]: Failed password for root from 172.16.5.5 port 22 ssh2
Jan 10 10:30:01 server sshd[1240]: Failed password for root from 10.9.8.7 port 22 ssh2
Jan 10 10:35:01 server sshd[1241]: Failed password for root from 172.16.5.5 port 22 ssh2
Jan 10 10:40:01 server sshd[1242]: Failed password for root from 192.168.1.100 port 22 ssh2
"""


def openssl(*args):
    return subprocess.run(
        ["openssl", *map(str, args)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )


def create_ca(directory, name):
    key = directory / f"{name}.key"
    cert = directory / f"{name}.pem"
    openssl(
        "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key, "-out", cert, "-days", "2",
        "-subj", f"/CN={name}"
    )
    return key, cert


def create_server(directory, name, ca_key, ca_cert):
    key = directory / f"{name}.key"
    csr = directory / f"{name}.csr"
    cert = directory / f"{name}.pem"
    openssl(
        "req", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key, "-out", csr, "-subj", f"/CN={name}"
    )
    openssl(
        "x509", "-req", "-in", csr, "-CA", ca_cert,
        "-CAkey", ca_key, "-CAcreateserial", "-out", cert,
        "-days", "2"
    )
    return cert


def install_certificates(ca_cert, server_cert):
    shutil.copyfile(ca_cert, HOME / "ca.pem")
    shutil.copyfile(server_cert, HOME / "server.pem")


def make_valid_baseline_inputs():
    (HOME / "sshd_config").write_text(BASELINE_CONFIG)
    (HOME / "auth.log").write_text(BASELINE_LOG)
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        ca_key, ca_cert = create_ca(directory, "BaselineCA")
        server_cert = create_server(directory, "BaselineServer", ca_key, ca_cert)
        install_certificates(ca_cert, server_cert)


def run_audit():
    if REPORT.exists():
        REPORT.unlink()
    result = subprocess.run(
        [str(EXECUTABLE)], capture_output=True, cwd=HOME, timeout=15
    )
    assert result.returncode == 0, (
        f"Execution of {EXECUTABLE} failed with return code {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert REPORT.is_file(), f"Report file {REPORT} was not created."


def expected_ssh(config_text):
    active = [line for line in config_text.splitlines() if not line.startswith("#")]
    return "YES" if (
        "PermitRootLogin no" in active and
        "PubkeyAuthentication yes" in active
    ) else "NO"


def expected_ips(log_text):
    counts = collections.Counter()
    for line in log_text.splitlines():
        if "Failed password" not in line:
            continue
        match = re.search(r"\bfrom\s+((?:\d{1,3}\.){3}\d{1,3})\b", line)
        if match:
            counts[match.group(1)] += 1
    found = sorted(ip for ip, count in counts.items() if count >= 3)
    return ", ".join(found) if found else "NONE"


def expected_certificate():
    result = subprocess.run(
        ["openssl", "verify", "-CAfile", str(HOME / "ca.pem"),
         str(HOME / "server.pem")],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return "YES" if result.returncode == 0 else "NO"


def assert_strict_report(config_text, log_text):
    expected = [
        f"SSH_HARDENED: {expected_ssh(config_text)}",
        f"CERT_VALID: {expected_certificate()}",
        f"MALICIOUS_IPS: {expected_ips(log_text)}",
    ]
    raw = REPORT.read_text()
    assert raw.splitlines() == expected, (
        f"Expected exactly {expected!r}, got {raw.splitlines()!r}"
    )
    assert raw in ("\n".join(expected), "\n".join(expected) + "\n"), (
        "Report contains extra whitespace or lines"
    )


def test_c_file_exists():
    path = "/home/user/sec_audit.c"
    assert os.path.isfile(path), f"Source file {path} does not exist."


def test_executable_exists_and_runs():
    c_file = "/home/user/sec_audit.c"
    exe_file = "/home/user/sec_audit"

    # Compile if not already compiled
    if not os.path.isfile(exe_file) and os.path.isfile(c_file):
        subprocess.run(["gcc", c_file, "-o", exe_file], capture_output=True)

    assert os.path.isfile(exe_file), f"Executable {exe_file} does not exist."
    assert os.access(exe_file, os.X_OK), f"File {exe_file} is not executable."

    make_valid_baseline_inputs()
    result = subprocess.run([exe_file], capture_output=True, cwd="/home/user", timeout=15)
    assert result.returncode == 0, f"Execution of {exe_file} failed with return code {result.returncode}."


def test_audit_report_content():
    report_file = "/home/user/audit_report.txt"
    assert os.path.isfile(report_file), f"Report file {report_file} was not created."

    with open(report_file, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) >= 3, f"Report file {report_file} does not contain the expected number of lines."

    ssh_hardened_found = False
    cert_valid_found = False
    malicious_ips_found = False

    for line in content:
        line = line.strip()
        if line.startswith("SSH_HARDENED:"):
            assert line == "SSH_HARDENED: NO", f"Expected 'SSH_HARDENED: NO', got '{line}'"
            ssh_hardened_found = True
        elif line.startswith("CERT_VALID:"):
            assert line == "CERT_VALID: YES", f"Expected 'CERT_VALID: YES', got '{line}'"
            cert_valid_found = True
        elif line.startswith("MALICIOUS_IPS:"):
            expected_ips_value = "10.9.8.7, 172.16.5.5"
            assert line == f"MALICIOUS_IPS: {expected_ips_value}", f"Expected 'MALICIOUS_IPS: {expected_ips_value}', got '{line}'"
            malicious_ips_found = True

    assert ssh_hardened_found, "SSH_HARDENED check missing from report."
    assert cert_valid_found, "CERT_VALID check missing from report."
    assert malicious_ips_found, "MALICIOUS_IPS check missing from report."
    assert len(content) == 3, "Report must contain exactly three lines."


def test_behavior_on_generated_inputs():
    rng = random.SystemRandom()
    ips = {
        f"10.{rng.randrange(1, 250)}.{rng.randrange(1, 250)}.{rng.randrange(1, 250)}",
        f"172.{rng.randrange(16, 31)}.{rng.randrange(1, 250)}.{rng.randrange(1, 250)}",
        f"192.0.2.{rng.randrange(1, 250)}",
    }
    while len(ips) < 3:
        ips.add(f"198.51.100.{rng.randrange(1, 250)}")
    ip_a, ip_b, ip_c = list(ips)[:3]

    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        good_ca_key, good_ca = create_ca(directory, "GeneratedGoodCA")
        good_server = create_server(directory, "GeneratedGoodServer", good_ca_key, good_ca)
        bad_ca_key, bad_ca = create_ca(directory, "GeneratedBadCA")
        bad_server = create_server(directory, "GeneratedBadServer", bad_ca_key, bad_ca)

        hardened_config = """Port 2222
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
"""
        entries = []
        for index, (ip, count) in enumerate(((ip_a, 3), (ip_b, 5), (ip_c, 2))):
            for attempt in range(count):
                entries.append(
                    f"Feb 20 12:{index}{attempt}:00 host sshd[{2000 + index * 10 + attempt}]: "
                    f"Failed password for invalid user audit from {ip} port 22 ssh2"
                )
        entries.append(
            f"Feb 20 13:00:00 host sshd[2999]: Accepted publickey for audit from {ip_c} port 22 ssh2"
        )
        rng.shuffle(entries)
        generated_log = "\n".join(entries) + "\n"

        (HOME / "sshd_config").write_text(hardened_config)
        (HOME / "auth.log").write_text(generated_log)
        install_certificates(good_ca, good_server)
        run_audit()
        assert_strict_report(hardened_config, generated_log)

        non_hardened_config = """# PermitRootLogin no
PermitRootLogin yes
PubkeyAuthentication yes
"""
        no_attack_log = (
            f"Mar 01 08:00:00 host sshd[3001]: Failed password for root from {ip_a} port 22 ssh2\n"
            f"Mar 01 08:01:00 host sshd[3002]: Failed password for root from {ip_a} port 22 ssh2\n"
            f"Mar 01 08:02:00 host sshd[3003]: Accepted publickey for user from {ip_b} port 22 ssh2\n"
        )
        (HOME / "sshd_config").write_text(non_hardened_config)
        (HOME / "auth.log").write_text(no_attack_log)
        install_certificates(good_ca, bad_server)
        run_audit()
        assert_strict_report(non_hardened_config, no_attack_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
