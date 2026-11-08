#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import time
import uuid

EXP_SCRIPT = "/home/user/scripts/check_health.exp"
BASH_SCRIPT = "/home/user/scripts/alert_manager.sh"
CLI_TOOL = "/home/user/legacy_app/cli_tool.sh"
STATE_FILE = "/home/user/legacy_app/internal_state.dat"
ALERTS_DIR = "/home/user/alerts"


def test_scripts_exist_and_executable():
    assert os.path.isfile(EXP_SCRIPT), f"Expect script {EXP_SCRIPT} does not exist."
    assert os.access(EXP_SCRIPT, os.X_OK), f"Expect script {EXP_SCRIPT} is not executable."

    assert os.path.isfile(BASH_SCRIPT), f"Bash script {BASH_SCRIPT} does not exist."
    assert os.access(BASH_SCRIPT, os.X_OK), f"Bash script {BASH_SCRIPT} is not executable."


def test_expect_script_uses_cli_supplies_pin_and_filters_output():
    token = uuid.uuid4().hex
    cli_backup = f"{CLI_TOOL}.verifier_backup_{token}"
    mock_state = f"/tmp/mock_cli_state_{token}"
    pin_log = f"/tmp/mock_cli_pin_{token}"

    os.replace(CLI_TOOL, cli_backup)
    try:
        mock_cli = f'''#!/bin/bash
printf 'Please enter diagnostic PIN: '
IFS= read -r pin
printf '%s\\n' "$pin" >> {pin_log}
if [ "$pin" != "8472" ]; then
    echo "Invalid PIN."
    exit 1
fi
echo "Initializing diagnostics..."
echo "Memory: OK"
echo "CPU: OK"
printf '[STATE] %s\\n' "$(cat {mock_state})"
echo "Diagnostics complete."
'''
        with open(CLI_TOOL, "w") as f:
            f.write(mock_cli)
        os.chmod(CLI_TOOL, 0o755)

        # Test both supported lifecycle states while making the directly readable
        # internal state disagree with the mock CLI's answer.
        for expected_state, decoy_state in [
            ("HEALTHY", "CRITICAL_ERROR"),
            ("CRITICAL_ERROR", "HEALTHY"),
        ]:
            with open(mock_state, "w") as f:
                f.write(expected_state + "\n")
            with open(STATE_FILE, "w") as f:
                f.write(decoy_state + "\n")

            # Running it through Expect verifies that the submitted artifact is
            # actually an Expect program rather than an arbitrary executable.
            result = subprocess.run(
                ["/usr/bin/expect", EXP_SCRIPT],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"check_health.exp failed with exit code {result.returncode}. "
                f"Stderr: {result.stderr}"
            )
            expected_line = f"[STATE] {expected_state}"
            assert result.stdout.splitlines() == [expected_line], (
                "check_health.exp must print only the [STATE] line; "
                f"got stdout: {result.stdout!r}"
            )

        assert os.path.isfile(pin_log), "The legacy CLI was not invoked by check_health.exp."
        with open(pin_log) as f:
            supplied_pins = [line.rstrip("\n") for line in f]
        assert supplied_pins == ["8472", "8472"], (
            f"check_health.exp did not supply PIN 8472 on each invocation: {supplied_pins!r}"
        )
    finally:
        if os.path.lexists(CLI_TOOL):
            os.remove(CLI_TOOL)
        os.replace(cli_backup, CLI_TOOL)
        for path in (mock_state, pin_log):
            if os.path.exists(path):
                os.remove(path)


def test_alert_manager_executes_check_health_and_uses_its_output():
    token = uuid.uuid4().hex
    exp_backup = f"{EXP_SCRIPT}.verifier_backup_{token}"
    probe_state = f"/tmp/expect_probe_state_{token}"
    probe_log = f"/tmp/expect_probe_log_{token}"

    os.replace(EXP_SCRIPT, exp_backup)
    try:
        # This remains a valid Expect script, so wrappers that explicitly invoke
        # /usr/bin/expect are tested as well as wrappers that execute it directly.
        probe = f'''#!/usr/bin/expect -f
set log_file [open "{probe_log}" a]
puts $log_file "invoked"
close $log_file
set state_file [open "{probe_state}" r]
set state [string trim [read $state_file]]
close $state_file
puts "[STATE] $state"
'''
        with open(EXP_SCRIPT, "w") as f:
            f.write(probe)
        os.chmod(EXP_SCRIPT, 0o755)

        if os.path.exists(ALERTS_DIR):
            shutil.rmtree(ALERTS_DIR)

        # The real application's state deliberately disagrees with the probe.
        with open(STATE_FILE, "w") as f:
            f.write("HEALTHY\n")
        with open(probe_state, "w") as f:
            f.write("CRITICAL_ERROR\n")

        result = subprocess.run([BASH_SCRIPT], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, (
            f"alert_manager.sh failed with exit code {result.returncode}. Stderr: {result.stderr}"
        )
        symlink_path = os.path.join(ALERTS_DIR, "active", "current_alert.link")
        assert os.path.islink(symlink_path), (
            "alert_manager.sh did not act on the state returned by check_health.exp."
        )
        assert os.path.isfile(probe_log), "alert_manager.sh did not execute check_health.exp."
        with open(probe_log) as f:
            first_invocations = len(f.readlines())
        assert first_invocations >= 1, "alert_manager.sh did not execute check_health.exp."

        with open(STATE_FILE, "w") as f:
            f.write("CRITICAL_ERROR\n")
        with open(probe_state, "w") as f:
            f.write("HEALTHY\n")

        result = subprocess.run([BASH_SCRIPT], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, (
            f"alert_manager.sh failed with exit code {result.returncode}. Stderr: {result.stderr}"
        )
        assert not os.path.exists(symlink_path), (
            "alert_manager.sh ignored the HEALTHY state returned by check_health.exp."
        )
        with open(probe_log) as f:
            second_invocations = len(f.readlines())
        assert second_invocations > first_invocations, (
            "alert_manager.sh did not execute check_health.exp on every run."
        )
    finally:
        if os.path.lexists(EXP_SCRIPT):
            os.remove(EXP_SCRIPT)
        os.replace(exp_backup, EXP_SCRIPT)
        for path in (probe_state, probe_log):
            if os.path.exists(path):
                os.remove(path)


def test_alert_manager_behavior():
    bash_script = "/home/user/scripts/alert_manager.sh"
    state_file = "/home/user/legacy_app/internal_state.dat"
    alerts_dir = "/home/user/alerts"

    # Clean up alerts directory to test behavior from scratch
    if os.path.exists(alerts_dir):
        shutil.rmtree(alerts_dir)

    # Test CRITICAL_ERROR state
    with open(state_file, "w") as f:
        f.write("CRITICAL_ERROR\n")

    # Run alert_manager.sh
    result = subprocess.run([bash_script], capture_output=True, text=True)
    assert result.returncode == 0, f"alert_manager.sh failed with exit code {result.returncode}. Stderr: {result.stderr}"

    active_dir = os.path.join(alerts_dir, "active")
    resolved_dir = os.path.join(alerts_dir, "resolved")
    symlink_path = os.path.join(active_dir, "current_alert.link")

    assert os.path.isdir(active_dir), f"Directory {active_dir} was not created."
    assert os.path.isdir(resolved_dir), f"Directory {resolved_dir} was not created."
    assert os.path.islink(symlink_path), f"Symlink {symlink_path} was not created."

    target_file = os.path.realpath(symlink_path)
    assert os.path.isfile(target_file), f"Symlink target {target_file} does not exist."
    assert target_file.startswith(active_dir), f"Symlink target {target_file} is not in {active_dir}."
    assert "incident_" in os.path.basename(target_file), f"Log file {target_file} does not match naming convention."

    with open(target_file, "r") as f:
        content = f.read().strip()
    assert content == "[STATE] CRITICAL_ERROR", f"Log file does not contain expected state string. Got: {content}"

    # Test Idempotency
    time.sleep(1) # Ensure timestamp would change if a new file was created
    subprocess.run([bash_script], check=True)

    # Check that no new files were created in active_dir (only the link and the one log)
    active_files = os.listdir(active_dir)
    assert len(active_files) == 2, f"Expected exactly 2 files in {active_dir} (link + log), but found {len(active_files)}. Idempotency failed."

    # Test HEALTHY state
    with open(state_file, "w") as f:
        f.write("HEALTHY\n")

    subprocess.run([bash_script], check=True)

    assert not os.path.exists(symlink_path), f"Symlink {symlink_path} was not deleted after recovery."

    resolved_files = os.listdir(resolved_dir)
    assert len(resolved_files) == 1, f"Expected exactly 1 file in {resolved_dir}, but found {len(resolved_files)}."

    resolved_file_path = os.path.join(resolved_dir, resolved_files[0])
    assert resolved_files[0] == os.path.basename(target_file), "Resolved file name does not match the original incident log name."

    with open(resolved_file_path, "r") as f:
        content = f.read().strip()
    assert content == "[STATE] CRITICAL_ERROR", "Resolved file content was modified."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
