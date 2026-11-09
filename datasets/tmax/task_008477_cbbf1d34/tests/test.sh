#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pwd
import re
import secrets
import subprocess
from pathlib import Path


def test_update_lb_script_exists_and_executable():
    script_path = "/home/user/update_lb.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_upstream_conf_content():
    log_path = "/home/user/deployment.log"
    conf_path = "/home/user/upstream.conf"

    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    assert os.path.isfile(conf_path), f"Configuration file {conf_path} does not exist."

    # Parse log file to determine expected healthy ports
    port_status = {}
    with open(log_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # Example line: [2023-11-01 10:00:00] [PORT: 8081] [STATUS: IN_PROGRESS]
            match = re.search(r'\[PORT:\s*(\d+)\]\s*\[STATUS:\s*([A-Z_]+)\]', line)
            if match:
                port = int(match.group(1))
                status = match.group(2)
                port_status[port] = status

    healthy_ports = sorted([p for p, s in port_status.items() if s == "SUCCESS"])

    expected_conf_lines = ["upstream backend_cluster {"]
    for port in healthy_ports:
        expected_conf_lines.append(f"    server 127.0.0.1:{port};")
    expected_conf_lines.append("}")
    expected_conf = "\n".join(expected_conf_lines)

    with open(conf_path, 'r') as f:
        actual_conf = f.read().strip()

    assert actual_conf == expected_conf, (
        f"Content of {conf_path} does not match expected output.\n"
        f"Expected:\n{expected_conf}\n\nActual:\n{actual_conf}"
    )


def test_cron_schedule_file():
    cron_path = "/home/user/lb.cron"
    assert os.path.isfile(cron_path), f"Cron file {cron_path} does not exist."

    with open(cron_path, 'r') as f:
        content = f.read().strip()

    # Regex to match every 5 minutes schedule
    cron_pattern = r'^(\*/5|0-59/5)\s+\*\s+\*\s+\*\s+\*\s+/home/user/update_lb\.sh$'
    lines = [line.strip() for line in content.splitlines() if line.strip() and not line.strip().startswith('#')]

    assert len(lines) == 1, f"Expected exactly one active cron line in {cron_path}, found {len(lines)}."

    match = re.match(cron_pattern, lines[0])
    assert match, f"Cron line '{lines[0]}' does not match the expected pattern for running every 5 minutes."


def _expected_from_log(log_text):
    port_status = {}
    for line in log_text.splitlines():
        match = re.search(r'\[PORT:\s*(\d+)\]\s*\[STATUS:\s*([A-Z_]+)\]', line)
        if match:
            port_status[int(match.group(1))] = match.group(2)

    lines = ["upstream backend_cluster {"]
    for port in sorted(port for port, status in port_status.items() if status == "SUCCESS"):
        lines.append(f"    server 127.0.0.1:{port};")
    lines.append("}")
    return "\n".join(lines)


def _make_fixture(rng, ports, healthy_ports):
    records = []

    # Every ultimately unhealthy port has an earlier SUCCESS, while every
    # ultimately healthy port starts non-successful. This exercises latest-entry semantics.
    initial = list(ports)
    rng.shuffle(initial)
    for port in initial:
        status = rng.choice(["FAILED", "IN_PROGRESS"]) if port in healthy_ports else "SUCCESS"
        records.append((port, status))

    for _ in range(12):
        records.append((rng.choice(ports), rng.choice(["SUCCESS", "FAILED", "IN_PROGRESS"])))

    final_order = list(ports)
    rng.shuffle(final_order)
    for port in final_order:
        status = "SUCCESS" if port in healthy_ports else rng.choice(["FAILED", "IN_PROGRESS"])
        records.append((port, status))

    lines = []
    for index, (port, status) in enumerate(records):
        hour = 10 + index // 60
        minute = index % 60
        lines.append(
            f"[2024-02-03 {hour:02d}:{minute:02d}:00] [PORT: {port}] [STATUS: {status}]"
        )
    return "\n".join(lines) + "\n"


def _run_script_as_user():
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        ["/home/user/update_lb.sh"],
        cwd="/home/user",
        env={**os.environ, "HOME": "/home/user", "USER": "user", "LOGNAME": "user"},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        preexec_fn=demote,
    )


def test_script_processes_changed_logs_when_executed():
    log_path = Path("/home/user/deployment.log")
    conf_path = Path("/home/user/upstream.conf")
    original_log = log_path.read_bytes()
    original_conf = conf_path.read_bytes() if conf_path.exists() else None

    rng = secrets.SystemRandom()
    ports = rng.sample(range(8100, 9900), 7)
    first_healthy = set(rng.sample(ports, 3))
    second_healthy = set(rng.sample(ports, 4))
    while second_healthy == first_healthy:
        second_healthy = set(rng.sample(ports, 4))

    fixtures = [
        _make_fixture(rng, ports, first_healthy),
        _make_fixture(rng, ports, second_healthy),
    ]

    try:
        for fixture in fixtures:
            log_path.write_text(fixture)
            if conf_path.exists():
                conf_path.unlink()

            result = _run_script_as_user()
            assert result.returncode == 0, (
                "update_lb.sh failed when run as user.\n"
                f"stdout:\n{result.stdout}\n"
                f"stderr:\n{result.stderr}"
            )
            assert conf_path.is_file(), "update_lb.sh did not generate /home/user/upstream.conf."

            expected = _expected_from_log(fixture)
            actual = conf_path.read_text().strip()
            assert actual == expected, (
                "update_lb.sh produced incorrect output for a changed deployment log.\n"
                f"Expected:\n{expected}\n\nActual:\n{actual}"
            )
    finally:
        log_path.write_bytes(original_log)
        if original_conf is None:
            if conf_path.exists():
                conf_path.unlink()
        else:
            conf_path.write_bytes(original_conf)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
