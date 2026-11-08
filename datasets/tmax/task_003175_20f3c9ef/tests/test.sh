#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
import time
import urllib.request

import pytest

HOME = "/home/user"
SERVICE_PATHS = ("/app/log_generator.py", "/app/telemetry_api.py", "/app/prom_scraper.sh")


def matching_processes(path):
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if path in argv:
                found.append((int(entry), argv))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found


def stop_old_services():
    me = os.getpid()
    pids = set()
    for path in SERVICE_PATHS:
        pids.update(pid for pid, _ in matching_processes(path) if pid != me)
    for pid in pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while pids and time.time() < deadline:
        pids = {pid for pid in pids if os.path.exists(f"/proc/{pid}")}
        time.sleep(0.1)
    for pid in pids:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


def run_setup():
    proc = subprocess.run(
        ["runuser", "-u", "user", "--", "/home/user/setup_env.sh"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
    )
    assert proc.returncode == 0, "setup_env.sh failed when executed as the unprivileged user"


def wait_for(predicate, timeout=12):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    if last_error:
        raise AssertionError(f"condition was not met: {last_error}")
    raise AssertionError("condition was not met before timeout")


@pytest.fixture(scope="session", autouse=True)
def execute_submission_setup():
    script_path = "/home/user/setup_env.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    stop_old_services()
    for path in (
        "/home/user/telemetry_link",
        "/home/user/telemetry_data",
        "/home/user/passwd_mock",
        "/home/user/group_mock",
        "/home/user/mock_fstab",
        "/home/user/scraper_output.log",
    ):
        if os.path.islink(path) or os.path.isfile(path):
            os.unlink(path)
        elif os.path.isdir(path):
            import shutil
            shutil.rmtree(path)

    # Execute twice from a clean state to verify that the requested setup is idempotent.
    run_setup()
    run_setup()
    yield


def test_setup_env_script():
    script_path = "/home/user/setup_env.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"


def test_passwd_group_mock():
    passwd_path = "/home/user/passwd_mock"
    group_path = "/home/user/group_mock"
    assert os.path.isfile(passwd_path), f"{passwd_path} does not exist"
    assert os.path.isfile(group_path), f"{group_path} does not exist"

    passwd_lines = [line.strip() for line in open(passwd_path) if line.strip() and not line.startswith("#")]
    group_lines = [line.strip() for line in open(group_path) if line.strip() and not line.startswith("#")]
    assert "cap-worker" in "\n".join(passwd_lines), "cap-worker not found in passwd_mock"
    assert "cap-planners" in "\n".join(group_lines), "cap-planners not found in group_mock"

    workers = [line.split(":") for line in passwd_lines if line.split(":", 1)[0] == "cap-worker"]
    planners = [line.split(":") for line in group_lines if line.split(":", 1)[0] == "cap-planners"]
    assert len(workers) == 1, "cap-worker must appear exactly once after repeated setup"
    assert len(planners) == 1, "cap-planners must appear exactly once after repeated setup"
    assert len(workers[0]) == 7, "cap-worker entry is not standard passwd format"
    assert len(planners[0]) == 4, "cap-planners entry is not standard group format"
    assert workers[0][2].isdigit() and workers[0][3].isdigit(), "mock UID and GID must be numeric"
    assert planners[0][2].isdigit(), "mock group GID must be numeric"
    assert workers[0][3] == planners[0][2], "cap-worker does not use the cap-planners mock GID"


def test_telemetry_dirs():
    data_dir = "/home/user/telemetry_data"
    link_path = "/home/user/telemetry_link"
    assert os.path.isdir(data_dir), f"{data_dir} does not exist or is not a directory"
    assert os.path.islink(link_path), f"{link_path} is not a symlink"
    assert os.readlink(link_path) == data_dir, f"{link_path} does not point to {data_dir}"


def test_mock_fstab():
    fstab_path = "/home/user/mock_fstab"
    assert os.path.isfile(fstab_path), f"{fstab_path} does not exist"
    content = open(fstab_path).read()
    matches = re.findall(r"^tmpfs\s+/home/user/telemetry_data\s+tmpfs\s+size=100M,gid=(\d+)\s+0\s+0\s*$", content, re.M)
    assert matches, "mock_fstab does not contain the correctly formatted tmpfs entry"
    assert len(matches) == 1, "mock_fstab entry was duplicated by repeated setup"
    group_gid = next(line.split(":")[2] for line in open("/home/user/group_mock") if line.split(":", 1)[0] == "cap-planners")
    assert matches[0] == group_gid, "mock_fstab does not use the cap-planners mock GID"


def test_services_are_running_with_correct_environment():
    def all_started():
        groups = [matching_processes(path) for path in SERVICE_PATHS]
        return groups if all(groups) else None

    groups = wait_for(all_started)
    assert all(len(group) == 1 for group in groups), "repeated setup must leave exactly one instance of each service"

    expected = {
        "/app/log_generator.py": b"LOG_PATH=/home/user/telemetry_link/usage.log",
        "/app/telemetry_api.py": b"DATA_SOURCE=/home/user/telemetry_link/usage.log",
    }
    for path, marker in expected.items():
        pid = matching_processes(path)[0][0]
        with open(f"/proc/{pid}/environ", "rb") as f:
            environment = f.read().split(b"\0")
        assert marker in environment, f"{path} is not running with the required environment variable"


def test_generator_api_and_scraper_are_live():
    usage_path = "/home/user/telemetry_link/usage.log"

    def valid_usage():
        if not os.path.isfile(usage_path):
            return False
        lines = [line.strip() for line in open(usage_path) if line.strip()]
        return lines if lines and re.fullmatch(r"CPU:\d+ MEM:\d+ IO:\d+", lines[-1]) else False

    wait_for(valid_usage)
    usage_size = os.path.getsize(usage_path)
    wait_for(lambda: os.path.getsize(usage_path) > usage_size, timeout=4)

    def fetch_metrics():
        with urllib.request.urlopen("http://127.0.0.1:5000/metrics", timeout=2) as response:
            data = json.loads(response.read().decode())
        return data if data.get("status") == "ok" and isinstance(data.get("latest_cpu"), int) else False

    metrics = wait_for(fetch_metrics)
    assert 0 <= metrics["latest_cpu"] <= 100

    log_path = "/home/user/scraper_output.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. Services might not be running properly."
    start_size = os.path.getsize(log_path)
    wait_for(lambda: os.path.getsize(log_path) > start_size, timeout=4)
    with open(log_path, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, "scraper_output.log is empty"
    valid_json_found = False
    for line in lines[-5:]:
        try:
            data = json.loads(line.strip())
            if data.get("status") == "ok" and "latest_cpu" in data:
                valid_json_found = True
                break
        except json.JSONDecodeError:
            continue
    assert valid_json_found, "Could not find valid JSON with 'status': 'ok' and 'latest_cpu' in recent scraper output"


def test_fuzz_equivalence():
    agent_script = "/home/user/forecast_calc.py"
    oracle_bin = "/app/oracle_forecaster"
    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist"
    assert not os.path.islink(agent_script), "forecast_calc.py must be a Python source file, not a symlink"
    assert os.path.isfile(oracle_bin), f"Oracle binary {oracle_bin} does not exist"

    source = open(agent_script, "rb").read()
    assert not source.startswith(b"\x7fELF"), "forecast_calc.py is not Python source"
    text = source.decode("utf-8")
    compile(text, agent_script, "exec")
    assert "oracle_forecaster" not in text, "forecast_calc.py must implement the calculation rather than invoke the oracle"

    cases = []
    random.seed(42)
    for _ in range(1000):
        cases.append((random.randint(0, 100), random.randint(0, 9999), random.randint(0, 999)))
    secure = secrets.SystemRandom()
    for _ in range(200):
        cases.append((secure.randint(0, 100), secure.randint(0, 9999), secure.randint(0, 999)))
    cases.extend([(0, 0, 0), (100, 9999, 999), (1, 3, 1), (99, 8192, 501)])

    expected = []
    inputs = []
    for cpu, mem, io in cases:
        input_str = f"CPU:{cpu} MEM:{mem} IO:{io}"
        inputs.append(input_str)
        oracle_proc = subprocess.run([oracle_bin, input_str], capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on input '{input_str}'"
        expected.append(oracle_proc.stdout.strip())

    # Make the oracle unavailable while submissions execute, so delegating to it cannot pass.
    old_mode = os.stat(oracle_bin).st_mode & 0o7777
    os.chmod(oracle_bin, 0)
    try:
        for input_str, oracle_out in zip(inputs, expected):
            agent_proc = subprocess.run(
                ["runuser", "-u", "user", "--", "python3", agent_script, input_str],
                capture_output=True,
                text=True,
                timeout=3,
            )
            assert agent_proc.returncode == 0, f"Agent script failed on input '{input_str}'"
            agent_out = agent_proc.stdout.strip()
            assert oracle_out == agent_out, f"Mismatch on input '{input_str}': oracle='{oracle_out}', agent='{agent_out}'"
    finally:
        os.chmod(oracle_bin, old_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
