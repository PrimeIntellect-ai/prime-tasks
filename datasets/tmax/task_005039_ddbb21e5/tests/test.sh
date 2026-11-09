#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import time
from pathlib import Path

import pytest

FSTAB = Path("/home/user/micro_fstab")
REPORT = Path("/home/user/service_report.json")
EXPECTED_SERVICES = {
    "svc_worker_alpha": (Path("/home/user/data/alpha_data"), Path("/home/user/mnt/alpha_link")),
    "svc_worker_beta": (Path("/home/user/data/beta_data"), Path("/home/user/mnt/beta_link")),
    "svc_worker_gamma": (Path("/home/user/data/gamma_data"), Path("/home/user/mnt/gamma_link")),
}


def find_script():
    candidates = [
        Path("/home/user/sync_mounts"),
        Path("/home/user/sync_mounts.py"),
        Path("/home/user/sync_mounts.sh"),
    ]
    scripts = [p for p in candidates if p.is_file() and not p.is_symlink()]
    assert scripts, "Automation script /home/user/sync_mounts (or sync_mounts.py/.sh) is missing."
    return scripts[0]


def run_script(script):
    if script.suffix == ".py":
        command = ["python3", str(script)]
    elif script.suffix == ".sh":
        command = ["bash", str(script)]
    else:
        assert os.access(script, os.X_OK), f"{script} is not executable and has no recognized interpreter suffix."
        command = [str(script)]

    result = subprocess.run(
        command,
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Automation script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_report():
    assert REPORT.is_file(), f"JSON report file {REPORT} is missing."
    try:
        with REPORT.open() as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {REPORT} is not valid JSON: {exc}")
    return data


def assert_state(expected):
    data = read_report()
    assert data == expected, f"JSON content in {REPORT} does not match the expected state. Got: {data}"

    for service, running in expected.items():
        source, link = EXPECTED_SERVICES[service]
        if running:
            assert source.is_dir(), f"Source directory {source} does not exist."
            assert link.is_symlink(), f"Symlink {link} does not exist or is not a symlink."
            assert os.readlink(link) == str(source), f"Symlink {link} does not point to {source}."
        else:
            assert not os.path.lexists(link), f"File or symlink {link} still exists, but {service} is not running."


def pids_with_comm(name):
    result = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if (proc / "comm").read_text().strip() == name:
                result.append(int(proc.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def stop_named_beta_processes():
    for pid in pids_with_comm("svc_worker_beta"):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while pids_with_comm("svc_worker_beta") and time.time() < deadline:
        time.sleep(0.05)
    assert not pids_with_comm("svc_worker_beta"), "Could not establish the stopped-service test state."


def test_automation_tracks_exact_process_state():
    assert FSTAB.is_file(), f"Configuration file {FSTAB} is missing."
    script = find_script()

    # The image starts none of the configured services. Establish that state and
    # verify the script removes every stale mount and reports every service false.
    stop_named_beta_processes()
    run_script(script)
    all_stopped = {name: False for name in EXPECTED_SERVICES}
    assert_state(all_stopped)

    # Exercise the automation with a real exact-name process. beta is 15 bytes,
    # so Linux exposes the complete name through /proc/<pid>/comm and pgrep -x.
    helper = Path("/tmp/svc_worker_beta")
    if os.path.lexists(helper):
        helper.unlink()
    helper.symlink_to("/bin/sleep")
    process = subprocess.Popen([str(helper), "120"])
    try:
        deadline = time.time() + 3
        while process.pid not in pids_with_comm("svc_worker_beta") and time.time() < deadline:
            time.sleep(0.05)
        assert process.pid in pids_with_comm("svc_worker_beta"), "Failed to start exact-name beta test process."

        run_script(script)
        beta_running = dict(all_stopped)
        beta_running["svc_worker_beta"] = True
        assert_state(beta_running)
    finally:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=5)
        if os.path.lexists(helper):
            helper.unlink()

    # Re-run after the process exits to ensure the link is removed and the final
    # report again reflects the actual all-stopped state.
    run_script(script)
    assert_state(all_stopped)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
