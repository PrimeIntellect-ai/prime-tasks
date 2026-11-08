#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import time
import uuid

import pytest


def test_bashrc_env_var():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist"

    with open(bashrc_path, "r") as f:
        content = f.read()

    match = re.search(r'export\s+DEPLOY_ENV=["\']?production["\']?', content)
    assert match is not None, "DEPLOY_ENV=production is not exported in /home/user/.bashrc"


def test_cron_job():
    try:
        result = subprocess.run(
            ["crontab", "-l", "-u", "user"], capture_output=True, text=True
        )
        crontab_content = result.stdout
    except FileNotFoundError:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        crontab_content = result.stdout

    cron_pattern = r'(?:\*/5|0,5,10,15,20,25,30,35,40,45,50,55)\s+\*\s+\*\s+\*\s+\*.*python3\s+/home/user/orchestrator\.py'
    match = re.search(cron_pattern, crontab_content)
    assert match is not None, "Cron job for orchestrator.py every 5 minutes is missing or incorrect"

    active_lines = [
        line.strip()
        for line in crontab_content.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    absolute_pattern = re.compile(
        r'(?:\*/5|0,5,10,15,20,25,30,35,40,45,50,55)\s+'
        r'\*\s+\*\s+\*\s+\*\s+.*'
        r'/usr/bin/python3\s+/home/user/orchestrator\.py(?:\s|$)'
    )
    assert any(absolute_pattern.match(line) for line in active_lines), (
        "Cron job must use /usr/bin/python3 and /home/user/orchestrator.py"
    )


def test_orchestrator_executable():
    orch_path = "/home/user/orchestrator.py"
    assert os.path.isfile(orch_path), f"{orch_path} does not exist"
    assert os.access(orch_path, os.X_OK), f"{orch_path} is not executable"


def process_command(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    except OSError:
        return []


def matching_processes(service_path):
    matches = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        command = process_command(int(entry))
        if len(command) >= 2 and command[0] == "/usr/bin/python3" and command[1] == service_path:
            matches.append(int(entry))
    return matches


def read_pid_file_exact(pid_file, expected_names):
    with open(pid_file, "r") as f:
        raw = f.read()

    assert raw, "services.pid is empty"
    lines = raw.split("\n")
    if lines[-1] == "":
        lines.pop()
    assert lines and all(lines), "services.pid contains blank lines"

    entries = []
    for line in lines:
        match = re.fullmatch(r'([^:\r\n]+):([1-9][0-9]*)', line)
        assert match is not None, f"Malformed PID file line: {line!r}"
        entries.append((match.group(1), int(match.group(2))))

    names = [name for name, _ in entries]
    assert len(names) == len(set(names)), "services.pid contains duplicate service entries"
    assert set(names) == set(expected_names), (
        f"services.pid entries {set(names)!r} do not exactly match discovered services "
        f"{set(expected_names)!r}"
    )
    return dict(entries)


def test_orchestrator_logic():
    orch_path = "/home/user/orchestrator.py"
    services_dir = "/home/user/services"
    pid_file = "/home/user/run/services.pid"

    suffix = uuid.uuid4().hex
    dynamic_names = [f"svc_{suffix}_one", f"svc_{suffix}_two"]
    dynamic_paths = [os.path.join(services_dir, name + ".py") for name in dynamic_names]
    marker_paths = [f"/tmp/{name}.started" for name in dynamic_names]
    tokens = [uuid.uuid4().hex, uuid.uuid4().hex]

    subprocess.run(["pkill", "-f", "/home/user/services/"], stderr=subprocess.DEVNULL)
    if os.path.exists(pid_file):
        os.remove(pid_file)

    for service_path, marker_path, token in zip(dynamic_paths, marker_paths, tokens):
        if os.path.exists(marker_path):
            os.remove(marker_path)
        with open(service_path, "w") as f:
            f.write(
                "import time\n"
                f"with open({marker_path!r}, 'w') as marker:\n"
                f"    marker.write({token!r})\n"
                "while True:\n"
                "    time.sleep(60)\n"
            )

    try:
        # Test 1: Silent failure when DEPLOY_ENV != production.
        env = os.environ.copy()
        env["DEPLOY_ENV"] = "staging"
        result = subprocess.run(
            ["/usr/bin/python3", orch_path], env=env, capture_output=True
        )
        assert result.returncode == 0, "Orchestrator should exit with 0 when DEPLOY_ENV != production"
        assert not os.path.exists(pid_file), "Orchestrator should not do anything when DEPLOY_ENV != production"
        assert result.stdout == b"" and result.stderr == b"", (
            "Orchestrator should silently reject a non-production environment"
        )
        assert not any(os.path.exists(path) for path in marker_paths), (
            "A service was launched outside the production environment"
        )

        # Seed a dead PID for a dynamically named service to require stale-entry updating.
        os.makedirs(os.path.dirname(pid_file), exist_ok=True)
        with open(pid_file, "w") as f:
            f.write(f"{dynamic_names[0]}:99999999\n")

        # Test 2: Successful execution and dynamic directory scanning.
        env["DEPLOY_ENV"] = "production"
        result = subprocess.run(
            ["/usr/bin/python3", orch_path], env=env, capture_output=True
        )
        assert result.returncode == 0, "Orchestrator failed to run successfully"

        time.sleep(1)
        assert os.path.isfile(pid_file), f"PID file {pid_file} was not created"

        expected_names = sorted(
            filename[:-3]
            for filename in os.listdir(services_dir)
            if filename.endswith(".py")
            and os.path.isfile(os.path.join(services_dir, filename))
        )
        pids = read_pid_file_exact(pid_file, expected_names)

        assert "alpha" in pids, "alpha service not found in services.pid"
        assert "beta" in pids, "beta service not found in services.pid"
        assert pids[dynamic_names[0]] != 99999999, "Stale PID entry was not updated"

        for marker_path, token in zip(marker_paths, tokens):
            assert os.path.isfile(marker_path), "A dynamically discovered service was not executed"
            with open(marker_path, "r") as f:
                assert f.read() == token, "Dynamic service did not execute its file contents"

        # Verify every recorded PID is live and is the corresponding service launched
        # through the required absolute Python interpreter.
        for name, pid in pids.items():
            try:
                os.kill(pid, 0)
            except OSError:
                pytest.fail(f"Service {name} with PID {pid} is not actually running")

            service_path = os.path.join(services_dir, name + ".py")
            command = process_command(pid)
            assert len(command) >= 2, f"Service {name} has no readable command line"
            assert command[0] == "/usr/bin/python3", (
                f"Service {name} was not launched using /usr/bin/python3"
            )
            assert command[1] == service_path, (
                f"PID for {name} is not executing {service_path}"
            )
            assert matching_processes(service_path) == [pid], (
                f"Expected exactly one running process for service {name}"
            )

        # A second run must preserve live PIDs and must not create duplicate launches
        # or duplicate/malformed PID-file entries.
        first_pids = dict(pids)
        result = subprocess.run(
            ["/usr/bin/python3", orch_path], env=env, capture_output=True
        )
        assert result.returncode == 0, "Orchestrator failed on repeated execution"
        time.sleep(0.5)

        second_pids = read_pid_file_exact(pid_file, expected_names)
        assert second_pids == first_pids, "Live services were launched again or their PIDs changed"
        for name, pid in second_pids.items():
            service_path = os.path.join(services_dir, name + ".py")
            assert matching_processes(service_path) == [pid], (
                f"Duplicate process launched for service {name}"
            )
    finally:
        subprocess.run(["pkill", "-f", "/home/user/services/"], stderr=subprocess.DEVNULL)
        for path in dynamic_paths + marker_paths:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        try:
            os.remove(pid_file)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
