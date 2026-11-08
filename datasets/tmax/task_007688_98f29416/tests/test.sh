#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import string
import subprocess


def test_net_users_conf_updated():
    conf_path = "/home/user/net_users.conf"
    assert os.path.exists(conf_path), f"File {conf_path} is missing."

    with open(conf_path, "r") as f:
        content = f.read().strip()

    expected_content = """alice:admin,users
bob:users
charlie:dev,users,netadmin
diana:netadmin,users"""

    assert content == expected_content, f"Content of {conf_path} does not match expected output."


def test_failed_ips_created():
    failed_ips_path = "/home/user/failed_ips.txt"
    assert os.path.exists(failed_ips_path), f"File {failed_ips_path} is missing."

    with open(failed_ips_path, "r") as f:
        content = f.read().strip()

    expected_content = """10.0.0.5\n10.10.10.10\n172.16.0.2"""
    assert content == expected_content, f"Content of {failed_ips_path} does not match expected extracted IPs."


def test_probe_log_archive_created():
    archive_path = "/home/user/probe.log.archive"
    assert os.path.exists(archive_path), f"File {archive_path} is missing."

    with open(archive_path, "r") as f:
        content = f.read().strip()

    expected_content = """2023-10-01T10:00:00 192.168.1.10 OK
2023-10-01T10:01:00 10.0.0.5 TIMEOUT
2023-10-01T10:02:00 172.16.0.2 DROP
2023-10-01T10:03:00 10.0.0.5 TIMEOUT
2023-10-01T10:04:00 192.168.1.20 OK
2023-10-01T10:05:00 10.10.10.10 DROP
2023-10-01T10:06:00 192.168.1.10 OK"""

    assert content == expected_content, f"Content of {archive_path} does not match the original log."


def test_probe_log_cleared():
    probe_log_path = "/home/user/probe.log"
    assert os.path.exists(probe_log_path), f"File {probe_log_path} is missing."
    assert os.path.getsize(probe_log_path) == 0, f"File {probe_log_path} is not empty."


def test_script_executes_and_processes_fresh_inputs():
    script_path = "/home/user/analyze_network.py"
    assert os.path.exists(script_path), f"File {script_path} is missing."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"File {script_path} is not a regular file."

    rng = random.SystemRandom()
    token = ''.join(rng.choice(string.ascii_lowercase) for _ in range(10))
    users = [
        f"zed_{token}:ops,audit",
        f"charlie:qa_{token},dev_{token}",
        f"amy_{token}:users",
        f"mira_{token}:netadmin,monitoring",
    ]
    conf_text = "\n".join(users) + "\n"

    ips = [
        f"10.{rng.randrange(1, 255)}.{rng.randrange(0, 256)}.{rng.randrange(1, 255)}",
        f"172.{rng.randrange(16, 32)}.{rng.randrange(0, 256)}.{rng.randrange(1, 255)}",
        f"192.168.{rng.randrange(0, 256)}.{rng.randrange(1, 255)}",
        f"203.0.113.{rng.randrange(1, 255)}",
    ]
    events = [
        (ips[0], "TIMEOUT"),
        (ips[1], "DROP"),
        (ips[0], "TIMEOUT"),
        (ips[2], "OK"),
        (ips[3], "DROP"),
        (ips[1], "OK"),
    ]
    rng.shuffle(events)
    log_lines = [
        f"2026-07-19T12:{index:02d}:00 {ip} {status}"
        for index, (ip, status) in enumerate(events)
    ]
    log_text = "\n".join(log_lines) + "\n"

    expected_conf_lines = []
    for line in users:
        username, groups = line.split(":", 1)
        if username == "charlie":
            groups = groups + ",netadmin"
        expected_conf_lines.append(f"{username}:{groups}")
    expected_conf = "\n".join(expected_conf_lines)
    expected_failed = sorted({
        line.split()[1]
        for line in log_lines
        if line.split()[2] in {"TIMEOUT", "DROP"}
    })

    with open("/home/user/net_users.conf", "w") as f:
        f.write(conf_text)
    with open("/home/user/probe.log", "w") as f:
        f.write(log_text)
    for path in ("/home/user/probe.log.archive", "/home/user/failed_ips.txt"):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["python3", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Executing {script_path} failed with exit code {result.returncode}. "
        f"stderr: {result.stderr}"
    )

    with open("/home/user/net_users.conf", "r") as f:
        assert f.read().strip() == expected_conf

    assert os.path.isfile("/home/user/failed_ips.txt")
    with open("/home/user/failed_ips.txt", "r") as f:
        assert f.read().strip().splitlines() == expected_failed

    assert os.path.isfile("/home/user/probe.log.archive")
    with open("/home/user/probe.log.archive", "r") as f:
        assert f.read() == log_text

    assert os.path.isfile("/home/user/probe.log")
    assert os.path.getsize("/home/user/probe.log") == 0
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
