#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import stat
import subprocess
import time

APP_DIR = "/home/user/app"
WRAPPER_SCRIPT = os.path.join(APP_DIR, "run_monitor.sh")
MONITOR_SCRIPT = os.path.join(APP_DIR, "mail_monitor.py")
OUTPUT_DIR = os.path.join(APP_DIR, "output")
LOG_FILE = os.path.join(OUTPUT_DIR, "report.log")


def test_wrapper_script_exists_and_executable():
    """Verify the wrapper script exists and is executable."""
    assert os.path.isfile(WRAPPER_SCRIPT), f"Wrapper script {WRAPPER_SCRIPT} is missing."
    st = os.stat(WRAPPER_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Wrapper script {WRAPPER_SCRIPT} is not executable."


def test_wrapper_script_contents():
    """Verify the wrapper script exports the variable and calls the python script."""
    with open(WRAPPER_SCRIPT, "r") as f:
        content = f.read()

    assert "SMTP_SERVER_IP" in content and "127.0.0.1" in content, \
        "Wrapper script does not seem to export SMTP_SERVER_IP='127.0.0.1'."
    assert "mail_monitor.py" in content, \
        "Wrapper script does not execute mail_monitor.py."


def test_monitor_script_contents():
    """Verify the Python script contains the required logic."""
    assert os.path.isfile(MONITOR_SCRIPT), f"Python script {MONITOR_SCRIPT} is missing."
    with open(MONITOR_SCRIPT, "r") as f:
        content = f.read()

    assert "127.0.0.1" in content, "Python script does not default to 127.0.0.1."
    assert "/home/user/app/output/report.log" in content, "Python script does not use the absolute path for the log file."
    assert "10255" in content, "Python script does not use port 10255."
    assert "STATUS: OK" in content, "Python script does not contain 'STATUS: OK'."
    assert "STATUS: ERROR" in content, "Python script does not contain 'STATUS: ERROR'."


def test_output_directory_and_log_exist():
    """Verify the output directory and log file exist."""
    assert os.path.isdir(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} was not created."
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} was not generated."


def test_log_contains_status_ok():
    """Verify the log created by the requested manual run contains STATUS: OK."""
    with open(LOG_FILE, "r") as f:
        content = f.read()

    assert "STATUS: OK" in content, "Log file does not contain 'STATUS: OK'. Ensure the wrapper script was executed manually."


def _clear_output():
    if os.path.isfile(LOG_FILE):
        os.unlink(LOG_FILE)
    if os.path.isdir(OUTPUT_DIR):
        try:
            os.rmdir(OUTPUT_DIR)
        except OSError:
            pass


def _run(command, env):
    return subprocess.run(
        command,
        cwd="/tmp",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


def _assert_exact_log(expected):
    assert os.path.isdir(OUTPUT_DIR), "The monitor did not create the output directory."
    assert os.path.isfile(LOG_FILE), "The monitor did not create the absolute report log."
    with open(LOG_FILE, "r") as f:
        assert f.read() == expected + "\n"


def _stop_smtp_server():
    """Stop the aiosmtpd instance started by the installed pytest wrapper."""
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ")
            if b"aiosmtpd" in cmdline and b"10255" in cmdline:
                os.kill(int(entry), 15)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    deadline = time.time() + 3
    while time.time() < deadline:
        sock = socket.socket()
        sock.settimeout(0.1)
        try:
            result = sock.connect_ex(("127.0.0.1", 10255))
        finally:
            sock.close()
        if result != 0:
            return
        time.sleep(0.05)
    raise AssertionError("Could not stop the SMTP test server on port 10255.")


def test_direct_script_defaults_to_localhost_and_connects():
    """With SMTP_SERVER_IP absent, the real script must connect and report success."""
    _clear_output()
    env = {"PATH": "/usr/local/bin:/usr/bin:/bin", "HOME": "/tmp"}
    result = _run(["python3", MONITOR_SCRIPT], env)
    assert result.returncode == 0, result.stderr
    _assert_exact_log("STATUS: OK")


def test_wrapper_overrides_scheduler_environment_and_runs_monitor():
    """The wrapper must override a hostile inherited value and run the monitor."""
    _clear_output()
    env = {
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": "/tmp",
        "SMTP_SERVER_IP": "127.0.0.2",
    }
    result = _run([WRAPPER_SCRIPT], env)
    assert result.returncode == 0, result.stderr
    _assert_exact_log("STATUS: OK")


def test_connection_failure_is_caught_and_logged():
    """The same localhost diagnostic must report ERROR once the server is absent."""
    _stop_smtp_server()
    _clear_output()
    env = {
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": "/tmp",
        "SMTP_SERVER_IP": "127.0.0.1",
    }
    result = _run(["python3", MONITOR_SCRIPT], env)
    assert result.returncode == 0, result.stderr
    _assert_exact_log("STATUS: ERROR")


def test_wrapper_executes_failure_path_too():
    """With the server still absent, invoking the wrapper must run the diagnostic."""
    _clear_output()
    env = {
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": "/tmp",
        "SMTP_SERVER_IP": "127.0.0.2",
    }
    result = _run([WRAPPER_SCRIPT], env)
    assert result.returncode == 0, result.stderr
    _assert_exact_log("STATUS: ERROR")
TEST_EOF

# Use the installed pytest launcher so its intended SMTP test service is active.
if /usr/local/bin/pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
