#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import time
import pytest

EXE = "/home/user/bin/interactive_daemon"
EXP = "/home/user/bin/auto_start.exp"
LAUNCH = "/home/user/bin/launch.sh"
LOG = "/home/user/daemon_logs/app.log"


def process_ids():
    return {int(name) for name in os.listdir("/proc") if name.isdigit()}


def process_exe(pid):
    try:
        return os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return None


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def same_executable(pid, path):
    try:
        return os.path.samefile(f"/proc/{pid}/exe", path)
    except OSError:
        return False


def test_executable_compiled():
    """Check if the C daemon was compiled to the correct location and is executable."""
    assert os.path.isfile(EXE), f"Executable not found at {EXE}"
    assert os.access(EXE, os.X_OK), f"File at {EXE} is not executable"
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File at {EXE} is not a compiled ELF executable"


def test_bashrc_environment():
    """Check if DAEMON_ENV=hardened is exported in .bashrc."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist"
    with open(bashrc_path, "r") as f:
        content = f.read()
    pattern = r"export\s+DAEMON_ENV\s*=\s*['\"]?hardened['\"]?"
    assert re.search(pattern, content), f"DAEMON_ENV=hardened is not exported in {bashrc_path}"


def test_expect_script():
    """Check if the expect script exists and contains the PIN."""
    assert os.path.isfile(EXP), f"Expect script not found at {EXP}"
    with open(EXP, "r") as f:
        content = f.read()
    assert "7924" in content, f"Expect script {EXP} does not contain the required PIN '7924'"
    assert EXE in content, f"Expect script {EXP} does not spawn {EXE}"
    assert "Enter Hardening PIN: " in content, "Expect script does not wait for the exact daemon prompt"


def test_launch_script():
    """Check if the launch script exists, is executable, and references required artifacts."""
    assert os.path.isfile(LAUNCH), f"Launch script not found at {LAUNCH}"
    assert os.access(LAUNCH, os.X_OK), f"Launch script at {LAUNCH} is not executable"
    with open(LAUNCH, "r") as f:
        content = f.read()
    assert "/home/user/.bashrc" in content, "Launch script does not source /home/user/.bashrc"
    assert EXP in content, f"Launch script does not execute {EXP}"
    assert LOG in content, f"Launch script does not redirect output to {LOG}"


def test_logrotate_config():
    """Check if the logrotate config is valid and contains all required directives."""
    conf_path = "/home/user/daemon_logrotate.conf"
    assert os.path.isfile(conf_path), f"Logrotate config not found at {conf_path}"
    with open(conf_path, "r") as f:
        content = f.read()

    assert LOG in content, f"Logrotate config does not target {LOG}"
    result = subprocess.run(["logrotate", "-d", conf_path], capture_output=True, text=True)
    assert result.returncode == 0, f"logrotate config failed validation: {result.stderr}"

    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    blocks = re.findall(r"([^{}]+)\{([^{}]*)\}", uncommented, flags=re.S)
    matching = [(header, body) for header, body in blocks if LOG in header]
    assert matching, f"No logrotate block targets {LOG}"
    body = matching[0][1]
    assert re.search(r"(?m)^\s*daily\s*$", body), "Logrotate block is missing 'daily'"
    assert re.search(r"(?m)^\s*rotate\s+4\s*$", body), "Logrotate block must keep exactly 4 rotations"
    assert re.search(r"(?m)^\s*compress\s*$", body), "Logrotate block is missing 'compress'"
    assert re.search(r"(?m)^\s*missingok\s*$", body), "Logrotate block is missing 'missingok'"
    assert re.search(r"(?m)^\s*notifempty\s*$", body), "Logrotate block is missing 'notifempty'"


def test_compiled_daemon_behavior():
    """Execute the compiled artifact and verify its required environment and interactive behavior."""
    env = os.environ.copy()
    env.pop("DAEMON_ENV", None)
    denied = subprocess.run([EXE], input="7924\n", text=True, capture_output=True, env=env, timeout=3)
    assert denied.returncode != 0, "Daemon ran without DAEMON_ENV=hardened"

    env["DAEMON_ENV"] = "hardened"
    proc = subprocess.Popen(
        [EXE], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, env=env
    )
    try:
        proc.stdin.write("7924\n")
        proc.stdin.flush()
        time.sleep(3.2)
        assert proc.poll() is None, "Daemon did not continue running after accepting the PIN"
    finally:
        if proc.poll() is None:
            proc.terminate()
        output, _ = proc.communicate(timeout=3)

    assert "Enter Hardening PIN: " in output, "Daemon did not emit the exact PIN prompt"
    assert "PIN accepted. Daemon initialized." in output, "Daemon did not accept the required PIN"
    assert output.count("STATUS: Daemon running securely...") >= 2, "Daemon did not continuously emit status output"


def test_daemon_execution_and_logs():
    """Execute the wrapper and require a fresh log plus live Expect and daemon processes."""
    before = process_ids()
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass

    subprocess.Popen(
        [LAUNCH],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(4.2)

    assert os.path.isfile(LOG), f"Log file not found at {LOG}. Did the wrapper script run?"
    with open(LOG, "r", errors="replace") as f:
        content = f.read()
    assert "PIN accepted. Daemon initialized." in content, "Log file does not indicate successful PIN acceptance."
    assert "STATUS: Daemon running securely..." in content, "Log file does not indicate the daemon is running securely."
    assert content.count("STATUS: Daemon running securely...") >= 2, "Fresh log does not show a continuously running daemon"

    new_pids = process_ids() - before
    daemon_pids = [pid for pid in new_pids if same_executable(pid, EXE)]
    assert daemon_pids, "Launching launch.sh did not leave the compiled daemon running"

    expect_pids = []
    for pid in new_pids:
        cmdline = process_cmdline(pid)
        exe = process_exe(pid)
        if EXP in cmdline and exe:
            try:
                if os.path.samefile(f"/proc/{pid}/exe", "/usr/bin/expect"):
                    expect_pids.append(pid)
            except OSError:
                pass
    assert expect_pids, "Launching launch.sh did not leave the Expect automation process running"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
