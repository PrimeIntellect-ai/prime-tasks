#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import random
import subprocess
import tempfile
import pytest

REMEDIATION = "/home/user/remediation"
BLOCKED = os.path.join(REMEDIATION, "blocked_ips.txt")
BLOCK_SH = os.path.join(REMEDIATION, "block.sh")
SECURE_CONFIG = os.path.join(REMEDIATION, "sshd_config_secure")
OLD_CONFIG = "/home/user/logs/sshd_config_old"
AUTH_LOG = "/home/user/logs/auth.log"
SOURCE = "/home/user/analyze_logs.c"
EXPECTED_IPS = {"192.168.1.100", "10.0.0.5"}


def test_remediation_dir_exists():
    path = REMEDIATION
    assert os.path.isdir(path), f"The directory {path} does not exist. Did you create it?"


def test_blocked_ips_txt():
    path = BLOCKED
    assert os.path.isfile(path), f"The file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ips = EXPECTED_IPS
    actual_ips = set(lines)

    assert actual_ips == expected_ips, (
        f"The file {path} does not contain the correct IPs. "
        f"Expected {expected_ips}, but found {actual_ips}."
    )
    assert len(lines) == 2, f"The file {path} should contain exactly 2 lines, but found {len(lines)}."


def test_block_sh():
    path = BLOCK_SH
    assert os.path.isfile(path), f"The file {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    expected_commands = [
        "iptables -A INPUT -s 192.168.1.100 -j DROP",
        "iptables -A INPUT -s 10.0.0.5 -j DROP"
    ]

    for cmd in expected_commands:
        assert cmd in content, (
            f"The required iptables command '{cmd}' was not found in {path}."
        )

    # Apart from blank lines, comments, and an optional shebang, every line must
    # be exactly one of the firewall commands required by blocked_ips.txt.
    active_lines = []
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        active_lines.append(line)
    assert len(active_lines) == len(expected_commands), (
        f"{path} must contain exactly one firewall command per blocked IP and no extra commands."
    )
    assert set(active_lines) == set(expected_commands), (
        f"{path} contains missing, duplicated, or unexpected active commands: {active_lines}"
    )


def test_sshd_config_secure():
    path = SECURE_CONFIG
    assert os.path.isfile(path), f"The file {path} does not exist."

    with open(path, "r") as f:
        lines = f.readlines()

    permit_root_login_no = False
    password_auth_no = False

    for line in lines:
        stripped = line.strip()
        # Ignore comments
        if stripped.startswith("#"):
            continue

        # Check for PermitRootLogin
        if re.search(r"^\s*PermitRootLogin\s+yes", stripped, re.IGNORECASE):
            pytest.fail(f"Found active 'PermitRootLogin yes' in {path}. It should be set to 'no'.")
        if re.search(r"^\s*PermitRootLogin\s+no", stripped, re.IGNORECASE):
            permit_root_login_no = True

        # Check for PasswordAuthentication
        if re.search(r"^\s*PasswordAuthentication\s+yes", stripped, re.IGNORECASE):
            pytest.fail(f"Found active 'PasswordAuthentication yes' in {path}. It should be set to 'no'.")
        if re.search(r"^\s*PasswordAuthentication\s+no", stripped, re.IGNORECASE):
            password_auth_no = True

    assert permit_root_login_no, f"'PermitRootLogin no' was not found as an active configuration in {path}."
    assert password_auth_no, f"'PasswordAuthentication no' was not found as an active configuration in {path}."

    # Confirm this is a modified copy: all non-security lines from the supplied
    # configuration must remain present verbatim.
    with open(OLD_CONFIG, "r") as f:
        old_lines = f.read().splitlines()
    secure_lines = [line.rstrip("\n") for line in lines]
    for old_line in old_lines:
        stripped = old_line.strip()
        directive = stripped.split(None, 1)[0].lower() if stripped and not stripped.startswith("#") else ""
        if directive not in {"permitrootlogin", "passwordauthentication"}:
            assert old_line in secure_lines, (
                f"The original configuration line {old_line!r} is missing from {path}."
            )

    # Every active occurrence of either hardened directive must be exactly 'no'.
    seen = {"permitrootlogin": 0, "passwordauthentication": 0}
    for raw in secure_lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = stripped.split()
        key = parts[0].lower()
        if key in seen:
            assert len(parts) == 2 and parts[1].lower() == "no", (
                f"Contradictory or malformed active directive in {path}: {raw!r}"
            )
            seen[key] += 1
    assert seen["permitrootlogin"] >= 1
    assert seen["passwordauthentication"] >= 1


def test_c_analyzer_compiles_and_handles_unseen_log():
    assert os.path.isfile(SOURCE), f"The C source file {SOURCE} does not exist."
    mode = os.lstat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"{SOURCE} must be a regular C source file."

    fd, executable = tempfile.mkstemp(prefix="analyze_logs_", dir="/tmp")
    os.close(fd)
    os.unlink(executable)
    compile_result = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"{SOURCE} did not compile successfully:\n{compile_result.stderr}"
    )

    rng = random.SystemRandom()
    candidates = []
    while len(candidates) < 5:
        ip = f"198.18.{rng.randrange(0, 256)}.{rng.randrange(1, 255)}"
        if ip not in candidates:
            candidates.append(ip)
    counts = [2, 3, 4, 5, 7]
    rng.shuffle(counts)
    cases = list(zip(candidates, counts)) + [("192.168.1.100", 1), ("10.0.0.5", 0)]
    expected = {ip for ip, count in cases if count > 3}

    generated_lines = []
    pid = 4000
    for ip, count in cases:
        generated_lines.append(
            f"Feb 20 09:00:00 server sshd[{pid}]: Accepted publickey for user from {ip} port 22 ssh2"
        )
        pid += 1
        for _ in range(count):
            generated_lines.append(
                f"Feb 20 09:00:01 server sshd[{pid}]: Failed password for invalid user probe from {ip} port 22 ssh2"
            )
            pid += 1
    rng.shuffle(generated_lines)
    generated_log = "\n".join(generated_lines) + "\n"

    with open(AUTH_LOG, "rb") as f:
        saved_log = f.read()
    with open(BLOCKED, "rb") as f:
        saved_blocked = f.read()

    try:
        with open(AUTH_LOG, "w") as f:
            f.write(generated_log)
        os.unlink(BLOCKED)
        run_result = subprocess.run(
            [executable],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert run_result.returncode == 0, (
            f"The compiled analyzer exited with {run_result.returncode}:\n{run_result.stderr}"
        )
        assert os.path.isfile(BLOCKED), "The compiled analyzer did not generate blocked_ips.txt."
        with open(BLOCKED, "r") as f:
            output_lines = [line.strip() for line in f if line.strip()]
        assert len(output_lines) == len(expected), (
            f"Analyzer produced duplicate, missing, or extra lines: {output_lines}; expected {expected}."
        )
        assert set(output_lines) == expected, (
            f"Analyzer failed on an unseen log. Expected {expected}, found {set(output_lines)}."
        )
    finally:
        with open(AUTH_LOG, "wb") as f:
            f.write(saved_log)
        with open(BLOCKED, "wb") as f:
            f.write(saved_blocked)
        if os.path.exists(executable):
            os.unlink(executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
