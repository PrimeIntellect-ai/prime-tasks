#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import mailbox
import os
import secrets
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

HOME = Path("/home/user")
REGISTER_TOOL = HOME / "bin/register_node.py"


@pytest.fixture(scope="session", autouse=True)
def execute_setup_twice_and_instrument_registration(tmp_path_factory):
    setup = HOME / "setup.sh"
    assert setup.is_file(), f"{setup} does not exist"
    assert os.access(setup, os.X_OK), f"{setup} is not executable"

    original_register = REGISTER_TOOL.read_bytes()
    original_mode = stat.S_IMODE(REGISTER_TOOL.stat().st_mode)
    nonce = secrets.token_hex(16)
    proof = Path("/tmp") / f"registration-proof-{nonce}"
    wrapper = f'''#!/usr/bin/env python3
import pathlib
import sys
node = input("Enter node name: ")
if node != "worker-01":
    sys.exit(1)
token = input("Enter auth token: ")
if token != "secret-token-99":
    sys.exit(1)
pathlib.Path({str(proof)!r}).write_text({nonce!r})
print("Registration successful")
'''.encode()

    try:
        REGISTER_TOOL.write_bytes(wrapper)
        REGISTER_TOOL.chmod(0o755)

        # The requested artifact is setup.sh. Remove its products so the tests
        # establish that executing setup.sh really creates and configures them.
        for path in [
            HOME / "monitor_env.sh",
            HOME / "register.exp",
            HOME / "monitor.py",
            HOME / "alerts.mbox",
            HOME / "monitor_state.json",
        ]:
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink(missing_ok=True)
        shutil.rmtree(HOME / "data_drop", ignore_errors=True)
        subprocess.run(["crontab", "-r"], capture_output=True)

        for attempt in (1, 2):
            result = subprocess.run(
                [str(setup)], capture_output=True, text=True, timeout=30
            )
            assert result.returncode == 0, (
                f"setup.sh failed on run {attempt}:\nstdout={result.stdout}\n"
                f"stderr={result.stderr}"
            )
            assert REGISTER_TOOL.read_bytes() == wrapper, (
                "setup.sh unexpectedly modified the supplied registration tool"
            )

        yield {"proof": proof, "nonce": nonce}
    finally:
        REGISTER_TOOL.write_bytes(original_register)
        REGISTER_TOOL.chmod(original_mode)
        proof.unlink(missing_ok=True)


def test_setup_script_exists_and_executable():
    path = "/home/user/setup.sh"
    assert os.path.isfile(path), f"{path} does not exist"
    assert os.access(path, os.X_OK), f"{path} is not executable"


def test_monitor_env_sh():
    path = "/home/user/monitor_env.sh"
    assert os.path.isfile(path), f"{path} does not exist"
    with open(path, "r") as f:
        content = f.read()
    assert "MONITOR_DIR=/home/user/data_drop" in content, "MONITOR_DIR not exported correctly"
    assert "SIZE_LIMIT=5000" in content, "SIZE_LIMIT not exported correctly"
    assert "ALERT_MAILBOX=/home/user/alerts.mbox" in content, "ALERT_MAILBOX not exported correctly"

    result = subprocess.run(
        [
            "bash", "-c",
            "source /home/user/monitor_env.sh && "
            "printf '%s\\n%s\\n%s\\n' \"$MONITOR_DIR\" \"$SIZE_LIMIT\" \"$ALERT_MAILBOX\" && "
            "env",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    lines = result.stdout.splitlines()
    assert lines[:3] == [
        "/home/user/data_drop", "5000", "/home/user/alerts.mbox"
    ]
    exported = set(lines[3:])
    assert "MONITOR_DIR=/home/user/data_drop" in exported
    assert "SIZE_LIMIT=5000" in exported
    assert "ALERT_MAILBOX=/home/user/alerts.mbox" in exported


def test_data_drop_directory():
    path = "/home/user/data_drop"
    assert os.path.isdir(path), f"{path} directory does not exist"


def test_register_exp(execute_setup_twice_and_instrument_registration):
    path = "/home/user/register.exp"
    assert os.path.isfile(path), f"{path} does not exist"
    assert os.access(path, os.X_OK), f"{path} is not executable"

    proof = execute_setup_twice_and_instrument_registration["proof"]
    nonce = execute_setup_twice_and_instrument_registration["nonce"]
    proof.unlink(missing_ok=True)

    result = subprocess.run([path], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"{path} failed to run: {result.stderr}"
    assert "Registration successful" in result.stdout, "Registration output incorrect"
    assert proof.is_file(), "register.exp did not complete the interactive registration"
    assert proof.read_text() == nonce


def test_cron_job_is_present_and_idempotent():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab"
    assert "monitor.py" in result.stdout, "monitor.py not found in crontab"
    assert "monitor_env.sh" in result.stdout, "monitor_env.sh not sourced in crontab"
    assert "* * * * *" in result.stdout, "Cron job not set to run every minute"

    active = [
        line.strip() for line in result.stdout.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
        and "/home/user/monitor.py" in line
    ]
    assert len(active) == 1, "Repeated setup.sh runs created duplicate monitor cron jobs"
    assert active[0].startswith("* * * * *")
    assert "/home/user/monitor_env.sh" in active[0]


def _subjects(path):
    box = mailbox.mbox(str(path), create=False)
    try:
        return [message.get("Subject") for message in box]
    finally:
        box.close()


def _all_json_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            if isinstance(key, str):
                yield key
            yield from _all_json_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _all_json_strings(item)


def test_monitor_py_functionality_with_derived_random_cases():
    monitor_script = Path("/home/user/monitor.py")
    data_dir = Path("/home/user/data_drop")
    mbox_file = Path("/home/user/alerts.mbox")
    state_file = Path("/home/user/monitor_state.json")

    assert monitor_script.is_file(), f"{monitor_script} does not exist"
    assert os.access(monitor_script, os.X_OK), f"{monitor_script} is not executable"

    # Isolate the behavioral test from files or state left by setup/registration.
    shutil.rmtree(data_dir, ignore_errors=True)
    data_dir.mkdir(parents=True)
    mbox_file.unlink(missing_ok=True)
    state_file.unlink(missing_ok=True)

    tag = secrets.token_hex(8)
    below = data_dir / f"below-{tag}.bin"
    equal = data_dir / f"equal-{tag}.bin"
    large1 = data_dir / f"large-{tag}.bin"
    below.write_bytes(os.urandom(4999))
    equal.write_bytes(os.urandom(5000))
    large1.write_bytes(os.urandom(5001))

    run_cmd = "source /home/user/monitor_env.sh && /home/user/monitor.py"
    subprocess.run(["bash", "-c", run_cmd], check=True, timeout=20)

    assert mbox_file.is_file(), f"{mbox_file} was not created"
    raw = mbox_file.read_bytes()
    assert raw.startswith(b"From "), "Mailbox is not in standard mbox format"

    expected1 = f"ALERT: Large file detected - {large1.name}"
    subjects = _subjects(mbox_file)
    assert subjects == [expected1], (
        "Monitor must alert only for files strictly larger than SIZE_LIMIT"
    )

    assert state_file.is_file(), f"{state_file} was not created"
    with state_file.open() as f:
        state = json.load(f)
    state_strings = set(_all_json_strings(state))
    assert str(large1.resolve()) in state_strings, (
        "JSON state does not track the alerted file by absolute path"
    )

    # A newly generated filename must alert, while the old path must not alert twice.
    large2 = data_dir / f"second-{secrets.token_hex(8)}.dat"
    large2.write_bytes(os.urandom(5000 + secrets.randbelow(2048) + 1))
    subprocess.run(["bash", "-c", run_cmd], check=True, timeout=20)

    expected2 = f"ALERT: Large file detected - {large2.name}"
    subjects = _subjects(mbox_file)
    assert subjects.count(expected1) == 1, "Duplicate alert was generated"
    assert subjects.count(expected2) == 1, "New oversized file was not detected"
    assert len(subjects) == 2, "Unexpected alerts were generated for boundary files"

    with state_file.open() as f:
        state = json.load(f)
    state_strings = set(_all_json_strings(state))
    assert str(large1.resolve()) in state_strings
    assert str(large2.resolve()) in state_strings
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
