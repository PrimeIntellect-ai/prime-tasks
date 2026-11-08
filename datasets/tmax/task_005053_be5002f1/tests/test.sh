#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
from collections import defaultdict

import pytest


def get_expected_brute_force_ips(log_path):
    counts = defaultdict(int)
    pattern = re.compile(r"Failed password for admin from (\S+)")
    with open(log_path, "r") as f:
        for line in f:
            match = pattern.search(line)
            if match:
                counts[match.group(1)] += 1
    return {ip for ip, count in counts.items() if count > 3}


def get_expected_sudo_users(sudoers_path):
    users = set()
    pattern = re.compile(r"^([a-zA-Z0-9_-]+)\s+.*NOPASSWD:\s*ALL\b")
    with open(sudoers_path, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("#"):
                continue
            match = pattern.match(line)
            if match:
                user = match.group(1)
                if user != "root":
                    users.add(user)
    return users


def get_expected_open_ports(ports_path):
    with open(ports_path, "r") as f:
        data = json.load(f)
    unauthorized = set()
    authorized = {22, 80, 443}
    for item in data:
        if item.get("state") == "open" and item.get("port") not in authorized:
            unauthorized.add(item.get("port"))
    return unauthorized


def validate_report(report_path, log_path, sudoers_path, ports_path):
    assert os.path.isfile(report_path), f"Compliance report missing at {report_path}"
    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Compliance report is not a valid JSON file.")

    expected_keys = {
        "brute_force_ips",
        "unauthorized_sudo_users",
        "unauthorized_open_ports",
    }
    assert set(report.keys()) == expected_keys, f"Report keys must exactly match {expected_keys}"

    expected_ips = get_expected_brute_force_ips(log_path)
    expected_users = get_expected_sudo_users(sudoers_path)
    expected_ports = get_expected_open_ports(ports_path)

    assert isinstance(report["brute_force_ips"], list), "'brute_force_ips' must be a list."
    assert set(report["brute_force_ips"]) == expected_ips, \
        f"Expected brute force IPs {expected_ips}, but got {set(report['brute_force_ips'])}"

    assert isinstance(report["unauthorized_sudo_users"], list), \
        "'unauthorized_sudo_users' must be a list."
    assert set(report["unauthorized_sudo_users"]) == expected_users, \
        f"Expected unauthorized sudo users {expected_users}, but got {set(report['unauthorized_sudo_users'])}"

    assert isinstance(report["unauthorized_open_ports"], list), \
        "'unauthorized_open_ports' must be a list."
    assert set(report["unauthorized_open_ports"]) == expected_ports, \
        f"Expected unauthorized open ports {expected_ports}, but got {set(report['unauthorized_open_ports'])}"


def test_compliance_report_exists():
    report_path = "/home/user/compliance_report.json"
    assert os.path.isfile(report_path), f"Compliance report missing at {report_path}"


def test_compliance_report_schema_and_content():
    validate_report(
        "/home/user/compliance_report.json",
        "/home/user/audit_env/logs/auth.log",
        "/home/user/audit_env/config/sudoers",
        "/home/user/audit_env/network/ports.json",
    )


def find_candidate_scripts():
    roots = ["/home/user", "/root", "/tmp", "/opt", "/usr/local/bin", "/workspace"]
    candidates = []
    seen = set()

    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [
                d for d in subdirs
                if os.path.join(directory, d) not in {"/home/user/audit_env", "/tmp/pytest-of-root"}
            ]
            for name in files:
                path = os.path.join(directory, name)
                real = os.path.realpath(path)
                if real in seen or real == "/tmp/test_final_state.py":
                    continue
                seen.add(real)
                try:
                    if not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, "rb") as f:
                        raw = f.read()
                    text = raw.decode("utf-8")
                except (OSError, UnicodeDecodeError):
                    continue

                suffix_ok = name.endswith((".py", ".sh", ".bash"))
                shebang_ok = text.startswith("#!") and ("python" in text.splitlines()[0] or "sh" in text.splitlines()[0])
                relevant = (
                    "/home/user/audit_env" in text
                    or "compliance_report.json" in text
                    or any(word in name.lower() for word in ("compliance", "audit", "policy"))
                )
                in_user_home = real.startswith("/home/user/") and not real.startswith("/home/user/audit_env/")
                if (suffix_ok or shebang_ok) and (relevant or in_user_home):
                    candidates.append(real)

    return sorted(set(candidates), key=lambda p: (0 if "/home/user/" in p else 1, p))


def commands_for_script(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            first = f.readline().lower()
    except OSError:
        first = ""

    if path.endswith(".py") or "python" in first:
        return [["python3", path]]
    if path.endswith((".sh", ".bash")) or "sh" in first:
        return [["bash", path]]
    return [[path], ["python3", path], ["bash", path]]


def write_scenario(log_text, sudoers_text, ports):
    with open("/home/user/audit_env/logs/auth.log", "w") as f:
        f.write(log_text)
    with open("/home/user/audit_env/config/sudoers", "w") as f:
        f.write(sudoers_text)
    with open("/home/user/audit_env/network/ports.json", "w") as f:
        json.dump(ports, f)


def test_script_dynamically_processes_changed_inputs():
    report_path = "/home/user/compliance_report.json"
    log_path = "/home/user/audit_env/logs/auth.log"
    sudoers_path = "/home/user/audit_env/config/sudoers"
    ports_path = "/home/user/audit_env/network/ports.json"

    candidates = find_candidate_scripts()
    assert candidates, "No Python or shell compliance-check script was found."

    scenarios = [
        (
            """Jan 1 host sshd[1]: Failed password for admin from 203.0.113.7 port 1 ssh2
Jan 1 host sshd[1]: Failed password for admin from 203.0.113.7 port 2 ssh2
Jan 1 host sshd[1]: Failed password for admin from 203.0.113.7 port 3 ssh2
Jan 1 host sshd[1]: Failed password for admin from 203.0.113.7 port 4 ssh2
Jan 1 host sshd[1]: Failed password for admin from 198.51.100.9 port 1 ssh2
Jan 1 host sshd[1]: Failed password for admin from 198.51.100.9 port 2 ssh2
Jan 1 host sshd[1]: Failed password for admin from 198.51.100.9 port 3 ssh2
Jan 1 host sshd[1]: Failed password for root from 192.0.2.4 port 1 ssh2
""",
            """root ALL=(ALL) NOPASSWD: ALL
alice ALL=(ALL) NOPASSWD: ALL
bob ALL=(ALL) NOPASSWD: /bin/ls
service-x ALL=(ALL:ALL) NOPASSWD:ALL
""",
            [
                {"port": 22, "state": "open", "service": "ssh"},
                {"port": 53, "state": "open", "service": "dns"},
                {"port": 8080, "state": "closed", "service": "proxy"},
                {"port": 65535, "state": "open", "service": "custom"},
            ],
        ),
        (
            """Feb 2 host sshd[2]: Failed password for admin from 10.20.30.40 port 10 ssh2
Feb 2 host sshd[2]: Failed password for admin from 10.20.30.40 port 11 ssh2
Feb 2 host sshd[2]: Failed password for admin from 10.20.30.40 port 12 ssh2
Feb 2 host sshd[2]: Failed password for admin from 10.20.30.40 port 13 ssh2
Feb 2 host sshd[2]: Failed password for admin from 10.20.30.40 port 14 ssh2
Feb 2 host sshd[2]: Accepted password for admin from 203.0.113.7 port 15 ssh2
""",
            """root ALL=(ALL:ALL) ALL
release_bot    ALL=(ALL)    NOPASSWD: ALL
operator ALL=(ALL) NOPASSWD: /usr/bin/id
""",
            [
                {"port": 80, "state": "open", "service": "http"},
                {"port": 443, "state": "open", "service": "https"},
                {"port": 12345, "state": "open", "service": "custom"},
                {"port": 53, "state": "closed", "service": "dns"},
            ],
        ),
    ]

    originals = {}
    for path in (report_path, log_path, sudoers_path, ports_path):
        with open(path, "rb") as f:
            originals[path] = f.read()

    errors = []
    try:
        for candidate in candidates:
            for command in commands_for_script(candidate):
                passed = True
                for log_text, sudoers_text, ports in scenarios:
                    write_scenario(log_text, sudoers_text, ports)
                    try:
                        os.remove(report_path)
                    except FileNotFoundError:
                        pass
                    try:
                        result = subprocess.run(
                            command,
                            cwd=os.path.dirname(candidate) or "/home/user",
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True,
                            timeout=15,
                        )
                        if result.returncode != 0:
                            raise AssertionError(
                                f"exit {result.returncode}: {result.stderr[-500:]}"
                            )
                        validate_report(report_path, log_path, sudoers_path, ports_path)
                    except Exception as exc:
                        errors.append(f"{candidate} via {command[0]}: {exc}")
                        passed = False
                        break
                if passed:
                    return
        pytest.fail(
            "No discovered script regenerated a correct report for changed audit inputs. "
            + " | ".join(errors[-8:])
        )
    finally:
        for path, data in originals.items():
            with open(path, "wb") as f:
                f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
