#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import pwd
import stat
import subprocess

USER = "user"
USER_INFO = pwd.getpwnam(USER)
UID = USER_INFO.pw_uid
RUNTIME_DIR = f"/run/user/{UID}"


def run_as_user(args, timeout=15, check=True):
    cmd = [
        "runuser", "-u", USER, "--",
        "env", f"HOME={USER_INFO.pw_dir}", f"USER={USER}",
        f"XDG_RUNTIME_DIR={RUNTIME_DIR}",
    ] + list(args)
    return subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, check=check)


def systemctl_show(unit, properties):
    args = ["systemctl", "--user", "show", unit]
    for prop in properties:
        args.extend(["--property", prop])
    result = run_as_user(args)
    values = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def test_binary_exists_and_executable():
    """Test that the compiled Rust binary exists at the correct location and is executable."""
    binary_path = "/home/user/bin/main-app"
    assert os.path.exists(binary_path), f"Binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable"

    st = os.stat(binary_path)
    assert stat.S_ISREG(st.st_mode), "main-app must be a regular compiled binary"
    assert st.st_uid == UID, "main-app was not installed as the unprivileged user"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "main-app is not an ELF executable"


def test_binary_actually_runs_correctly():
    """Execute the submitted artifact and verify the behavior of the supplied Rust program."""
    log_dir = "/home/user/logs"
    log_path = os.path.join(log_dir, "app.log")
    assert os.path.isdir(log_dir), "init-env.service did not create the log directory"
    assert os.path.exists(os.path.join(log_dir, "tz_info")), "init-env.service did not create tz_info"

    before = b""
    if os.path.exists(log_path):
        with open(log_path, "rb") as f:
            before = f.read()

    result = run_as_user(["/home/user/bin/main-app"], timeout=5, check=False)
    assert result.returncode == 0, f"main-app failed when executed: {result.stderr}"
    with open(log_path, "rb") as f:
        after = f.read()
    expected = b"Application log entry.\n" * 10
    assert after == before + expected, "main-app did not append the ten expected log entries"


def test_service_dependencies_fixed():
    """Test that main-app.service has the correct dependencies configured."""
    service_path = "/home/user/.config/systemd/user/main-app.service"
    assert os.path.exists(service_path), f"Service file not found at {service_path}"

    with open(service_path, "r") as f:
        content = f.read()

    assert re.search(r"After\s*=\s*init-env\.service", content), "main-app.service is missing 'After=init-env.service'"
    assert re.search(r"Requires\s*=\s*init-env\.service", content), "main-app.service is missing 'Requires=init-env.service'"

    values = systemctl_show("main-app.service", [
        "LoadState", "After", "Requires", "ExecMainStatus", "Result",
        "ExecMainStartTimestampMonotonic", "FragmentPath"
    ])
    assert values.get("LoadState") == "loaded", "systemd has not loaded main-app.service"
    assert "init-env.service" in values.get("After", "").split(), "loaded unit is not ordered after init-env.service"
    assert "init-env.service" in values.get("Requires", "").split(), "loaded unit does not require init-env.service"
    assert values.get("FragmentPath") == service_path, "systemd loaded main-app.service from an unexpected path"
    assert int(values.get("ExecMainStartTimestampMonotonic", "0")) > 0, "main-app.service was never started"
    assert values.get("ExecMainStatus") == "0", "main-app.service did not exit successfully"
    assert values.get("Result") == "success", "main-app.service has not completed successfully"

    init_values = systemctl_show("init-env.service", ["LoadState", "ActiveState", "ExecMainStatus", "Result"])
    assert init_values.get("LoadState") == "loaded", "init-env.service is not loaded"
    assert init_values.get("ActiveState") == "active", "required init-env.service is not active"
    assert init_values.get("ExecMainStatus") == "0", "init-env.service did not run successfully"
    assert init_values.get("Result") == "success", "init-env.service result is not successful"


def test_log_rotation_successful():
    """Test that log rotation was forced and created the rotated log file."""
    rotated_log_path = "/home/user/logs/app.log.1"
    assert os.path.exists(rotated_log_path), f"Rotated log file not found at {rotated_log_path}. Did you force logrotate?"
    assert os.path.isfile(rotated_log_path), "app.log.1 is not a regular file"
    assert os.path.getsize(rotated_log_path) > 0, "app.log.1 is empty"
    with open(rotated_log_path, "r", errors="replace") as f:
        rotated = f.read()
    assert "Application log entry." in rotated, "app.log.1 does not contain application output"

    state_path = "/home/user/logrotate.state"
    assert os.path.isfile(state_path), "The requested logrotate state file was not created"
    with open(state_path, "r", errors="replace") as f:
        state = f.read()
    assert state.startswith("logrotate state -- version "), "logrotate.state is not a valid logrotate state file"
    assert re.search(r'"/home/user/logs/app\.log"\s+\d{4}-\d{1,2}-\d{1,2}-\d{1,2}:\d{1,2}:\d{1,2}', state), \
        "logrotate.state has no rotation record for app.log"

    result = run_as_user([
        "logrotate", "--debug", "--state", state_path, "/home/user/logrotate.conf"
    ], timeout=15, check=False)
    assert result.returncode == 0, f"logrotate rejects the submitted configuration/state: {result.stderr}"
    debug_output = result.stdout + result.stderr
    assert "/home/user/logs/app.log" in debug_output, "logrotate did not process the configured application log"


def test_service_status_reported():
    """Test that the service status was saved and indicates an active state."""
    status_file = "/home/user/service_status.txt"
    assert os.path.exists(status_file), f"Service status report not found at {status_file}"

    with open(status_file, "r") as f:
        content = f.read()

    assert "active" in content.lower(), f"Service status does not indicate it is active in {status_file}"
    assert re.search(r"(?m)^\s*Active:\s+active\s+\(running\)", content), \
        "service_status.txt is not a status captured while main-app.service was running"
    assert "main-app.service" in content and re.search(r"(?m)^\s*Loaded:", content), \
        "service_status.txt does not look like systemctl status output for main-app.service"


def test_log_dir_listing_reported():
    """Test that the log directory listing was saved and contains the expected files."""
    listing_file = "/home/user/log_dir_listing.txt"
    assert os.path.exists(listing_file), f"Log directory listing not found at {listing_file}"

    with open(listing_file, "r") as f:
        content = f.read()

    assert "app.log" in content, f"'app.log' missing from {listing_file}"
    assert "app.log.1" in content, f"'app.log.1' missing from {listing_file}"
    assert os.path.isfile("/home/user/logs/app.log"), "Current app.log is missing"
    assert os.path.isfile("/home/user/logs/app.log.1"), "Rotated app.log.1 is missing"

    for name in ("app.log", "app.log.1"):
        assert re.search(rf"(?m)(^|\s){re.escape(name)}($|\s)", content), \
            f"{name} is not present as an entry in the saved directory listing"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
