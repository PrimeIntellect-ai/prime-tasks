#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import socket
import subprocess
import time
from pathlib import Path


def test_symlink_exists_and_correct():
    symlink_path = "/home/user/operator-data/inputs/legacy"
    target_path = "/home/user/legacy-manifests"

    assert os.path.islink(symlink_path), f"Expected '{symlink_path}' to be a symlink. It is missing or not a symlink."
    actual_target = os.readlink(symlink_path)
    assert actual_target == target_path, f"Symlink '{symlink_path}' points to '{actual_target}', expected '{target_path}'."


def test_compiled_yaml_exists_and_contains_manifests():
    compiled_path = "/home/user/operator-data/outputs/compiled.yaml"
    assert os.path.isfile(compiled_path), f"File '{compiled_path}' does not exist. The operator script may have failed or was not configured correctly."

    with open(compiled_path, "r") as f:
        content = f.read()

    assert "name: app1" in content, f"'{compiled_path}' does not contain the expected app1 manifest content. Check your directory structure and symlink."
    assert "name: app2-svc" in content, f"'{compiled_path}' does not contain the expected app2 manifest content."


def test_operator_log_exists_and_contains_output():
    log_path = "/home/user/operator-data/operator.log"
    assert os.path.isfile(log_path), f"File '{log_path}' does not exist. Ensure the operator script ran successfully."

    with open(log_path, "r") as f:
        content = f.read()

    assert "Applying manifests" in content, f"'{log_path}' is missing the expected dummy kubectl output. Ensure the PATH was updated correctly in the profile."


def test_status_log_exists_and_contains_metrics_status():
    status_path = "/home/user/operator-data/outputs/status.log"
    assert os.path.isfile(status_path), f"File '{status_path}' does not exist. Ensure check_metrics.sh was created and executed."

    with open(status_path, "r") as f:
        content = f.read()

    assert "METRICS_UP=1" in content, f"'{status_path}' does not contain 'METRICS_UP=1'. Check the logic in check_metrics.sh."


def test_profile_and_operator_structure():
    profile = Path("/home/user/.operator_profile")
    assert profile.is_file(), "Missing /home/user/.operator_profile"

    profile_commands = [
        line.strip() for line in profile.read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    assert len(profile_commands) == 2, ".operator_profile must contain only the two required exports"
    names = []
    for command in profile_commands:
        assert not any(token in command for token in ("$(`", "`", ";", "&&", "||", ">", "<")), \
            ".operator_profile contains unexpected shell logic"
        match = re.match(r"^export\s+(MANIFEST_DIR|PATH)=", command)
        assert match, ".operator_profile must use export for MANIFEST_DIR and PATH"
        names.append(match.group(1))
    assert sorted(names) == ["MANIFEST_DIR", "PATH"]

    result = subprocess.run(
        ["/usr/bin/env", "-i", "/bin/bash", "-c", "source /home/user/.operator_profile; /usr/bin/env -0"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    environment = {}
    for entry in result.stdout.split(b"\0"):
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            environment[key.decode()] = value.decode()
    assert environment.get("MANIFEST_DIR") == "/home/user/operator-data"
    assert environment.get("PATH", "").split(":")[0] == "/home/user/dummy-bin"

    operator = Path("/home/user/operator-sync.sh")
    assert operator.is_file() and os.access(operator, os.X_OK)
    commands = [
        line.strip() for line in operator.read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#") and not line.startswith("#!")
    ]
    assert commands, "operator-sync.sh has no executable commands"
    assert re.match(r"^(?:source|\.)\s+['\"]?/home/user/\.operator_profile['\"]?$", commands[0]), \
        "operator-sync.sh must source .operator_profile before doing anything else"
    assert commands[1:] == [
        'mkdir -p "$MANIFEST_DIR/outputs"',
        'cat "$MANIFEST_DIR"/inputs/legacy/*.yaml > "$MANIFEST_DIR/outputs/compiled.yaml" 2>/dev/null',
        'kubectl apply -f "$MANIFEST_DIR/outputs/compiled.yaml" --dry-run=client >> "$MANIFEST_DIR/operator.log" 2>/dev/null',
    ], "The original operator logic must remain unchanged"

    expected_cron = '#!/bin/bash\nenv -i /bin/bash -c "/home/user/operator-sync.sh"\n'
    assert Path("/home/user/mock-cron.sh").read_text() == expected_cron, "mock-cron.sh must remain unchanged"


def test_scheduler_recreates_outputs_from_both_manifests():
    compiled = Path("/home/user/operator-data/outputs/compiled.yaml")
    operator_log = Path("/home/user/operator-data/operator.log")
    compiled.unlink(missing_ok=True)
    operator_log.unlink(missing_ok=True)

    result = subprocess.run(
        ["/home/user/mock-cron.sh"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, f"mock-cron.sh failed: {result.stderr}"
    assert compiled.is_file(), "Running the scheduler did not create compiled.yaml"
    assert operator_log.is_file(), "Running the scheduler did not create operator.log"

    expected = b"".join(Path(path).read_bytes() for path in sorted(glob.glob("/home/user/legacy-manifests/*.yaml")))
    assert compiled.read_bytes() == expected, "compiled.yaml is not the exact concatenation of all legacy manifests"
    assert operator_log.read_text() == \
        "Applying manifests: apply -f /home/user/operator-data/outputs/compiled.yaml --dry-run=client\n"


def test_metrics_script_is_executable_and_checks_live_connectivity():
    script = Path("/home/user/check_metrics.sh")
    status = Path("/home/user/operator-data/outputs/status.log")
    assert script.is_file(), "Missing /home/user/check_metrics.sh"
    assert os.access(script, os.X_OK), "/home/user/check_metrics.sh is not executable"
    first_line = script.read_text().splitlines()[0] if script.read_text().splitlines() else ""
    assert re.match(r"^#!.*\bbash\b", first_line), "check_metrics.sh must be a bash script"

    subprocess.run(["pkill", "-f", "python3 -m http.server 8080"], check=False)
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                time.sleep(0.1)
        except OSError:
            break
    else:
        raise AssertionError("Could not make the metrics endpoint unavailable for the connectivity test")

    status.unlink(missing_ok=True)
    try:
        down = subprocess.run([str(script)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)
    except subprocess.TimeoutExpired:
        raise AssertionError("check_metrics.sh did not terminate while the metrics service was unavailable")
    assert down.stdout != "METRICS_UP=1\n", "check_metrics.sh reports success when no metrics service is reachable"
    assert not status.exists() or "METRICS_UP=1" not in status.read_text(), \
        "check_metrics.sh logged success while the metrics service was unavailable"

    server = subprocess.Popen(
        ["python3", "-m", "http.server", "8080", "--bind", "127.0.0.1"],
        cwd="/home/user", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            raise AssertionError("Verifier could not start the local metrics service")

        status.unlink(missing_ok=True)
        up = subprocess.run([str(script)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)
        assert up.returncode == 0, f"check_metrics.sh failed against a reachable service: {up.stderr}"
        assert up.stdout == "METRICS_UP=1\n", "check_metrics.sh must output exactly METRICS_UP=1"
        assert status.read_text() == "METRICS_UP=1\n", "check_metrics.sh did not append the exact success line to status.log"
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
