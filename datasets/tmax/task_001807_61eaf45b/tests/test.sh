#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import shlex
import secrets
import subprocess


def test_symlink_created_correctly():
    symlink_path = "/home/user/logs/current"
    target_path = "/home/user/app_data/logs"

    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symbolic link."
    actual_target = os.readlink(symlink_path)
    assert actual_target == target_path, f"Symlink points to {actual_target}, expected {target_path}."


def test_wrapper_script_updated():
    wrapper_path = "/home/user/monitor/run_monitor.sh"
    assert os.path.isfile(wrapper_path), f"Wrapper script {wrapper_path} is missing."

    with open(wrapper_path, "r") as f:
        content = f.read()

    assert "TZ=UTC" in content, "Wrapper script does not contain 'TZ=UTC'."
    assert "LC_ALL=C" in content, "Wrapper script does not contain 'LC_ALL=C'."

    commands = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            commands.append(line)

    def exported_values(line):
        try:
            words = shlex.split(line)
        except ValueError:
            return None
        if not words or words[0] != "export":
            return None
        values = {}
        for word in words[1:]:
            if "=" in word:
                name, value = word.split("=", 1)
                values[name] = value
        return values

    correctly_ordered = False
    for index, command in enumerate(commands):
        try:
            words = shlex.split(command)
        except ValueError:
            continue
        if "/home/user/monitor/check_health.py" not in words:
            continue

        values = {}
        previous = index - 1
        while previous >= 0:
            exported = exported_values(commands[previous])
            if exported is None:
                break
            values.update(exported)
            previous -= 1

        if values.get("TZ") == "UTC" and values.get("LC_ALL") == "C":
            correctly_ordered = True
            break

    assert correctly_ordered, (
        "TZ=UTC and LC_ALL=C must be exported in the commands immediately "
        "preceding execution of check_health.py."
    )


def test_status_file_created():
    status_file = "/home/user/monitor/status.txt"
    assert os.path.isfile(status_file), f"Status file {status_file} was not created. Did you run the wrapper script?"

    with open(status_file, "r") as f:
        content = f.read().strip()

    expected_text = "HEALTHY: ALL CHECKS PASSED"
    assert content == expected_text, f"Status file content is '{content}', expected '{expected_text}'."


def test_check_health_script_unmodified():
    script_path = "/home/user/monitor/check_health.py"
    assert os.path.isfile(script_path), f"Python script {script_path} is missing."

    expected_content = """import os
import time
import sys

# Check timezone
if os.environ.get("TZ") != "UTC":
    print("FAIL: Expected TZ=UTC environment variable")
    sys.exit(1)

# Check locale
if os.environ.get("LC_ALL") != "C":
    print("FAIL: Expected LC_ALL=C environment variable")
    sys.exit(1)

# Check symlink path
log_file = "/home/user/logs/current/app.log"
if not os.path.exists(log_file):
    print(f"FAIL: Log file not found at {log_file}")
    sys.exit(1)

# If all pass, write status
with open("/home/user/monitor/status.txt", "w") as f:
    f.write("HEALTHY: ALL CHECKS PASSED\\n")
print("SUCCESS: Health check passed")
"""
    with open(script_path, "r") as f:
        actual_contentFox = f.read()

    assert actual_contentFox == expected_content, "The check_health.py script was modified, which violates the constraints."


def test_wrapper_really_executes_health_check_with_required_environment():
    wrapper_path = "/home/user/monitor/run_monitor.sh"
    script_path = "/home/user/monitor/check_health.py"
    status_path = "/home/user/monitor/status.txt"
    marker_path = f"/tmp/monitor_probe_{secrets.token_hex(16)}"
    token = secrets.token_hex(32)

    with open(script_path, "rb") as f:
        original_script = f.read()
    original_mode = os.stat(script_path).st_mode

    probe = f'''import os
import sys

if os.environ.get("TZ") != "UTC":
    sys.exit(21)
if os.environ.get("LC_ALL") != "C":
    sys.exit(22)
if not os.path.exists("/home/user/logs/current/app.log"):
    sys.exit(23)
with open({marker_path!r}, "w") as marker:
    marker.write({token!r})
'''

    env = os.environ.copy()
    env.pop("TZ", None)
    env.pop("LC_ALL", None)

    try:
        with open(script_path, "w") as f:
            f.write(probe)
        if os.path.exists(status_path):
            os.unlink(status_path)

        result = subprocess.run(
            ["/bin/bash", wrapper_path],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )

        assert result.returncode == 0, (
            "The wrapper failed when run with TZ and LC_ALL removed from the verifier environment.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(marker_path), "The wrapper did not execute check_health.py."
        with open(marker_path, "r") as f:
            assert f.read() == token, "The health-check execution probe did not complete correctly."
    finally:
        with open(script_path, "wb") as f:
            f.write(original_script)
        os.chmod(script_path, original_mode)
        if os.path.exists(marker_path):
            os.unlink(marker_path)

    if os.path.exists(status_path):
        os.unlink(status_path)
    result = subprocess.run(
        ["/bin/bash", wrapper_path],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        "The repaired wrapper did not successfully run the original health check.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(status_path), "Running the wrapper did not recreate status.txt."
    with open(status_path, "r") as f:
        assert f.read().strip() == "HEALTHY: ALL CHECKS PASSED"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
