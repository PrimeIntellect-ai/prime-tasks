#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import socket
import stat
import subprocess
import time
from pathlib import Path

import pytest

RUNNER = Path("/home/user/run_cost_analysis.sh")
EXPECT_SCRIPT = Path("/home/user/fetch_metrics.exp")
EMULATOR = Path("/home/user/cloud_emulator.sh")
SSH_MOCK = Path("/home/user/cloud_ssh_mock")
WORK = Path("/tmp/finops_verify")
EXPECTED = 'COST_OPTS: {"spot": 0.04, "on_demand": 0.12}'


def port_open():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.3)
    try:
        return s.connect_ex(("127.0.0.1", 8080)) == 0
    finally:
        s.close()


def wait_for_port(wanted, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if port_open() == wanted:
            return True
        time.sleep(0.05)
    return port_open() == wanted


def remove_path(path):
    path = Path(path)
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def test_scripts_exist_and_executable():
    """Check that the orchestrator and expect scripts exist and are executable."""
    for script in [RUNNER, EXPECT_SCRIPT]:
        assert script.is_file(), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_required_script_structure():
    """Ensure the submitted files contain the required lifecycle mechanisms."""
    runner = RUNNER.read_text(errors="replace")
    expect = EXPECT_SCRIPT.read_text(errors="replace")

    assert runner.startswith("#!") and "bash" in runner.splitlines()[0], \
        "The orchestrator must use Bash."
    assert "/home/user/cloud_emulator.sh" in runner, \
        "The orchestrator does not start the supplied emulator."
    assert re.search(r"=\s*\$!", runner), \
        "The orchestrator does not capture the background emulator PID with $!."
    assert re.search(r"\b(while|until)\b", runner), \
        "The orchestrator does not contain a polling loop."
    assert ("/dev/tcp" in runner or re.search(r"\bnc\b[^\n]*8080", runner)), \
        "The polling loop does not actively test TCP port 8080."
    assert "/home/user/fetch_metrics.exp" in runner, \
        "The orchestrator does not execute the required Expect script."
    assert "cost.log" in runner, \
        "The Expect output is not redirected to cost.log."

    pid_vars = re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\$!", runner)
    assert pid_vars, "No variable captures the emulator PID."
    assert any(re.search(r"\bkill\b[^\n]*\$\{?" + re.escape(var) + r"\}?", runner)
               for var in pid_vars), \
        "The captured emulator PID is not used for cleanup."

    required_tokens = [
        "spawn", "/home/user/cloud_ssh_mock", "Password: ", "finops2024",
        "Emulator> ", "fetch_cost", "exit"
    ]
    position = -1
    for token in required_tokens:
        position = expect.find(token, position + 1)
        assert position >= 0, f"Expect script is missing or misorders required token: {token!r}"


def test_actual_artifacts_and_lifecycle():
    """Execute both submitted artifacts against instrumented dependencies."""
    assert not port_open(), "Port 8080 was already open before verification."

    remove_path(WORK)
    WORK.mkdir(mode=0o777)
    os.chmod(WORK, 0o777)

    originals = {}
    for path in [EMULATOR, SSH_MOCK, EXPECT_SCRIPT]:
        originals[path] = (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))

    submitted_expect = WORK / "submitted_fetch.exp"
    submitted_expect.write_bytes(originals[EXPECT_SCRIPT][0])
    os.chmod(submitted_expect, originals[EXPECT_SCRIPT][1] | 0o111)

    emulator_fixture = r'''#!/bin/bash
set -u
echo "$$" > /tmp/finops_verify/emulator.pid
sleep 2
python3 -m http.server 8080 --bind 127.0.0.1 >/dev/null 2>&1 &
PY_PID=$!
echo ready > /tmp/finops_verify/emulator.ready
cleanup() {
    trap - EXIT INT TERM
    kill "$PY_PID" 2>/dev/null || true
    wait "$PY_PID" 2>/dev/null || true
    echo terminated > /tmp/finops_verify/emulator.terminated
    exit 0
}
trap cleanup EXIT INT TERM
wait "$PY_PID"
'''
    ssh_fixture = r'''#!/bin/bash
echo invoked >> /tmp/finops_verify/ssh.trace
read -p "Password: " -s pass
echo
echo "PASS=$pass" >> /tmp/finops_verify/ssh.trace
if [ "$pass" != "finops2024" ]; then
    echo "Access denied"
    exit 1
fi
while true; do
    echo -n "Emulator> "
    IFS= read -r cmd || exit 1
    echo "CMD=$cmd" >> /tmp/finops_verify/ssh.trace
    if [ "$cmd" = "fetch_cost" ]; then
        if nc -z 127.0.0.1 8080; then
            echo 'COST_OPTS: {"spot": 0.04, "on_demand": 0.12}'
        else
            echo "ERROR: backend unavailable"
            exit 2
        fi
    elif [ "$cmd" = "exit" ]; then
        exit 0
    else
        echo "Unknown command"
        exit 3
    fi
done
'''

    server = None
    try:
        EMULATOR.write_text(emulator_fixture)
        SSH_MOCK.write_text(ssh_fixture)
        os.chmod(EMULATOR, 0o755)
        os.chmod(SSH_MOCK, 0o755)

        # Execute the submitted Expect script itself and verify its conversation.
        server = subprocess.Popen(
            ["python3", "-m", "http.server", "8080", "--bind", "127.0.0.1"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        assert wait_for_port(True), "Could not start the verifier's temporary backend."
        result = subprocess.run(
            ["runuser", "-u", "user", "--", str(submitted_expect)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
        )
        assert result.returncode == 0, f"Expect script failed:\n{result.stdout}"
        assert EXPECTED in result.stdout, \
            f"Expect script did not fetch metrics. Output:\n{result.stdout}"
        trace = (WORK / "ssh.trace").read_text()
        assert "PASS=finops2024" in trace
        assert "CMD=fetch_cost" in trace
        assert "CMD=exit" in trace

        server.terminate()
        server.wait(timeout=3)
        server = None
        assert wait_for_port(False), "Temporary backend did not stop."

        # Wrap the submitted Expect file so the orchestrator must execute the
        # required path; the wrapper then runs the already-tested submission.
        EXPECT_SCRIPT.write_text(
            "#!/bin/bash\n"
            "echo invoked > /tmp/finops_verify/expect.invoked\n"
            "exec /tmp/finops_verify/submitted_fetch.exp\n"
        )
        os.chmod(EXPECT_SCRIPT, 0o755)
        (WORK / "ssh.trace").unlink(missing_ok=True)

        for path in ["/home/user/finops", "/home/user/var/log/finops",
                     "/home/user/var/data/finops"]:
            remove_path(path)

        result = subprocess.run(
            ["runuser", "-u", "user", "--", str(RUNNER)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
        )
        assert result.returncode == 0, f"Orchestrator failed:\n{result.stdout}"
        assert (WORK / "expect.invoked").is_file(), \
            "The orchestrator did not execute /home/user/fetch_metrics.exp."
        assert (WORK / "emulator.ready").is_file(), \
            "The orchestrator did not start the supplied emulator."
        assert (WORK / "emulator.terminated").is_file(), \
            "The captured emulator process was not gracefully terminated."

        trace = (WORK / "ssh.trace").read_text()
        assert "PASS=finops2024" in trace
        assert "CMD=fetch_cost" in trace
        assert "CMD=exit" in trace
        assert wait_for_port(False), \
            "Port 8080 remains open after the orchestrator completed."
    finally:
        if server is not None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()

        pid_file = WORK / "emulator.pid"
        if pid_file.exists():
            try:
                os.kill(int(pid_file.read_text().strip()), 15)
            except (ValueError, ProcessLookupError, PermissionError):
                pass

        for path, (data, mode) in originals.items():
            path.write_bytes(data)
            os.chmod(path, mode)


def test_directories_and_symlinks():
    """Check that the required directories and symlinks are created correctly."""
    dirs_to_check = [
        "/home/user/var/log/finops",
        "/home/user/var/data/finops",
        "/home/user/finops"
    ]
    for d in dirs_to_check:
        assert os.path.isdir(d), f"Directory {d} does not exist."

    symlinks_to_check = {
        "/home/user/finops/logs": "/home/user/var/log/finops",
        "/home/user/finops/data": "/home/user/var/data/finops"
    }
    for link, target in symlinks_to_check.items():
        assert os.path.islink(link), f"{link} is not a symlink."
        assert os.readlink(link) == target, f"Symlink {link} does not point to {target}."


def test_log_file_content():
    """Check that the cost log file exists and contains the expected output."""
    log_file = "/home/user/finops/logs/cost.log"
    assert os.path.isfile(log_file), \
        f"Log file {log_file} does not exist. Did the script run successfully?"
    with open(log_file, "r") as f:
        content = f.read()
    assert EXPECTED in content, \
        f"Log file does not contain the expected cost metrics. Found: {content}"


def test_port_8080_is_closed():
    """Check that no process is listening on port 8080 (cleanup was successful)."""
    assert not port_open(), \
        "Port 8080 is still open. The background emulator process was not properly terminated."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
