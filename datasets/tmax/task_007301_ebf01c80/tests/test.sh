#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import socket
import subprocess
import threading

HOME = "/home/user"
BACKUP = f"{HOME}/backups/bashrc.bak"
BASHRC = f"{HOME}/.bashrc"
SOURCE = f"{HOME}/uptime_checker.cpp"
EXECUTABLE = f"{HOME}/check_uptime"
LOG = f"{HOME}/sre_uptime.log"


def test_backup_exists_and_matches_original_content():
    assert os.path.isfile(BACKUP), f"Backup file {BACKUP} does not exist."
    assert os.path.isfile(BASHRC), f"{BASHRC} does not exist."

    with open(BACKUP, "rb") as f:
        backup = f.read()
    with open(BASHRC, "rb") as f:
        current = f.read()

    assert b"SRE_MONITOR_PORT=5922" not in backup, \
        "The backup already contains the newly appended monitor setting."
    assert current.startswith(backup), \
        "bashrc.bak is not an unchanged copy of the original .bashrc content."
    assert b"SRE_MONITOR_PORT=5922" in current[len(backup):], \
        ".bashrc does not append the SRE_MONITOR_PORT=5922 setting after the backed-up content."


def test_bashrc_contains_env_var():
    with open(BASHRC, "r") as f:
        content = f.read()
    assert "SRE_MONITOR_PORT=5922" in content, \
        f"{BASHRC} does not set SRE_MONITOR_PORT=5922."


def test_source_and_executable_exist_and_compile():
    assert os.path.isfile(SOURCE), f"C++ source file {SOURCE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."

    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled executable."

    rebuilt = "/tmp/rebuilt_check_uptime"
    result = subprocess.run(
        ["g++", SOURCE, "-o", rebuilt], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"C++ source does not compile:\n{result.stderr}"


def make_server(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    actual_port = server.getsockname()[1]
    server.listen(1)
    server.settimeout(5)

    def accept_one():
        try:
            conn, _ = server.accept()
            conn.close()
        except OSError:
            pass
        finally:
            try:
                server.close()
            except OSError:
                pass

    thread = threading.Thread(target=accept_one, daemon=True)
    thread.start()
    return server, thread, actual_port


def choose_closed_port():
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return port


def assert_one_run(executable, use_default, should_be_up):
    server = None
    thread = None

    if use_default:
        port = 5900
        if should_be_up:
            server, thread, _ = make_server(port)
        else:
            probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            try:
                probe.bind(("127.0.0.1", port))
            except OSError as exc:
                raise AssertionError(f"Default test port 5900 is unexpectedly occupied: {exc}")
            finally:
                probe.close()
    elif should_be_up:
        server, thread, port = make_server(0)
    else:
        port = choose_closed_port()

    env = os.environ.copy()
    if use_default:
        env.pop("SRE_MONITOR_PORT", None)
    else:
        env["SRE_MONITOR_PORT"] = str(port)

    before = b""
    if os.path.exists(LOG):
        with open(LOG, "rb") as f:
            before = f.read()

    try:
        result = subprocess.run(
            [executable], env=env, capture_output=True, timeout=8
        )
        assert result.returncode == 0, f"{executable} failed to run."
    finally:
        if thread is not None:
            thread.join(timeout=6)
        if server is not None:
            try:
                server.close()
            except OSError:
                pass

    assert os.path.isfile(LOG), f"Log file {LOG} was not created."
    with open(LOG, "rb") as f:
        after = f.read()

    expected = b"STATUS: VNC_UP\n" if should_be_up else b"STATUS: VNC_DOWN\n"
    assert after == before + expected, \
        f"Expected exactly {expected!r} to be appended for port {port}."


def test_randomized_tcp_behavior_and_default_port():
    rebuilt = "/tmp/rebuilt_check_uptime"
    if os.path.exists(LOG):
        os.remove(LOG)

    scenarios = []
    for executable in (EXECUTABLE, rebuilt):
        scenarios.extend([
            (executable, True, False),
            (executable, True, True),
        ])
        for _ in range(3):
            scenarios.append((executable, False, False))
            scenarios.append((executable, False, True))

    random.SystemRandom().shuffle(scenarios)
    for executable, use_default, should_be_up in scenarios:
        assert_one_run(executable, use_default, should_be_up)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
