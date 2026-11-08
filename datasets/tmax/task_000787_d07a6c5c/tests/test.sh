#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile


def test_bashrc_contains_export():
    """Check if MAX_STORAGE_MB is set to 40 and exported in .bashrc."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"File {bashrc_path} does not exist."

    with open(bashrc_path, 'r') as f:
        content = f.read()

    assert re.search(r'^[^#]*MAX_STORAGE_MB\s*=\s*"?40"?', content, re.MULTILINE), \
        "MAX_STORAGE_MB=40 is not set in .bashrc."

    assert re.search(r'^[^#]*export\s+.*MAX_STORAGE_MB', content, re.MULTILINE) or \
           re.search(r'^[^#]*export\s+MAX_STORAGE_MB\s*=\s*"?40"?', content, re.MULTILINE), \
        "MAX_STORAGE_MB is not exported in .bashrc."


def test_monitor_sh_executable():
    """Check if monitor.sh exists, is executable, and sources .bashrc."""
    script_path = "/home/user/monitor.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, 'r') as f:
        content = f.read()
    assert re.search(r'^\s*(?:source|\.)\s+["\']?/home/user/\.bashrc["\']?(?:\s|$)',
                     content, re.MULTILINE), \
        "monitor.sh does not source /home/user/.bashrc."


def test_health_log_contents():
    """Check that the initial data was evaluated exactly once."""
    log_path = "/home/user/health.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        content = f.read()

    expected_log = "CRITICAL: Storage at 45MB exceeds limit of 40MB"
    assert expected_log in content, \
        f"Expected log entry '{expected_log}' not found in {log_path}. Found:\n{content}"

    size = int(subprocess.check_output(
        ["du", "-sm", "/home/user/telemetry_data"], text=True
    ).split()[0])
    dynamic_expected = (
        f"CRITICAL: Storage at {size}MB exceeds limit of 40MB"
        if size > 40 else
        f"OK: Storage at {size}MB within limit"
    )
    assert content.splitlines() == [dynamic_expected], \
        f"health.log must contain exactly one correct entry; found:\n{content}"


def test_monitor_behavior_on_derived_inputs():
    """Execute monitor.sh and verify both branches, sourcing, sizing, and appending."""
    script_path = "/home/user/monitor.sh"
    bashrc_path = "/home/user/.bashrc"
    data_path = "/home/user/telemetry_data"
    log_path = "/home/user/health.log"

    with open(bashrc_path, "rb") as f:
        original_bashrc = f.read()
    bashrc_mode = stat.S_IMODE(os.stat(bashrc_path).st_mode)
    with open(log_path, "rb") as f:
        original_log = f.read()
    log_mode = stat.S_IMODE(os.stat(log_path).st_mode)

    backup_dir = tempfile.mkdtemp(prefix="telemetry_backup_", dir="/home/user")
    os.rmdir(backup_dir)
    os.rename(data_path, backup_dir)

    try:
        os.mkdir(data_path)
        cases = [(2, "critical"), (5, "ok")]

        for megabytes, branch in cases:
            for name in os.listdir(data_path):
                path = os.path.join(data_path, name)
                if os.path.isdir(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)

            payload = os.path.join(data_path, "probe.dat")
            with open(payload, "wb") as f:
                block = b"X" * (1024 * 1024)
                for _ in range(megabytes):
                    f.write(block)
                f.flush()
                os.fsync(f.fileno())

            size = int(subprocess.check_output(
                ["du", "-sm", data_path], text=True
            ).split()[0])
            limit = max(0, size - 1) if branch == "critical" else size

            with open(bashrc_path, "w") as f:
                f.write(f"export MAX_STORAGE_MB={limit}\n")

            seed = "existing health entry"
            with open(log_path, "w") as f:
                f.write(seed + "\n")

            env = os.environ.copy()
            env["MAX_STORAGE_MB"] = "999999"
            result = subprocess.run(
                [script_path], env=env, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            assert result.returncode == 0, \
                f"monitor.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"

            if size > limit:
                expected = f"CRITICAL: Storage at {size}MB exceeds limit of {limit}MB"
            else:
                expected = f"OK: Storage at {size}MB within limit"

            with open(log_path, "r") as f:
                lines = f.read().splitlines()
            assert lines == [seed, expected], \
                f"monitor.sh did not append exactly the expected entry: {lines!r}"
    finally:
        if os.path.exists(data_path):
            shutil.rmtree(data_path)
        os.rename(backup_dir, data_path)
        with open(bashrc_path, "wb") as f:
            f.write(original_bashrc)
        os.chmod(bashrc_path, bashrc_mode)
        with open(log_path, "wb") as f:
            f.write(original_log)
        os.chmod(log_path, log_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
