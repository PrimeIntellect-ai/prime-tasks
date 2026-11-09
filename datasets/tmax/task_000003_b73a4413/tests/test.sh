#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import socket
import stat
import subprocess
import tarfile
import time

import pytest

SOURCE = "/home/user/edge_daemon.cpp"
DAEMON = "/home/user/edge_daemon"
SOCKET = "/home/user/run/edge.sock"
CLIENT = "/home/user/client.py"
LOG = "/home/user/data/sensor.log"
SCRIPT = "/home/user/backup_job.sh"
BACKUPS = [f"/home/user/backups/backup_{i}.tar.gz" for i in range(1, 4)]
EXPECTED_LOG = b"SENSOR_DATA_OK: 42.0\n"


def daemon_pids():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            if os.path.realpath(f"/proc/{name}/exe") == DAEMON:
                found.append(int(name))
        except OSError:
            pass
    return found


def test_cpp_source_modified():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "/home/user/run/edge.sock" in content, (
        f"File {SOURCE} does not contain the correct socket path '/home/user/run/edge.sock'."
    )
    assert "/tmp/app.sock" not in content, (
        f"File {SOURCE} still contains the old incorrect socket path '/tmp/app.sock'."
    )
    result = subprocess.run(
        ["g++", "-fsyntax-only", SOURCE], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"Modified C++ source does not compile:\n{result.stderr}"


def test_daemon_compiled():
    assert os.path.isfile(DAEMON), f"Executable {DAEMON} is missing."
    assert os.access(DAEMON, os.X_OK), f"File {DAEMON} is not executable."
    with open(DAEMON, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{DAEMON} is not a compiled ELF executable."


def test_run_daemon_and_client_and_cleanup():
    assert not daemon_pids(), "edge_daemon was still running; it was not cleaned up."
    assert not os.path.lexists(SOCKET), f"Stale daemon socket remains at {SOCKET}."
    if os.path.exists(LOG):
        os.remove(LOG)

    proc = subprocess.Popen([DAEMON], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                out, err = proc.communicate()
                pytest.fail(f"Daemon exited before creating its socket: {err.decode(errors='replace')}")
            if os.path.exists(SOCKET):
                mode = os.stat(SOCKET).st_mode
                assert stat.S_ISSOCK(mode), f"{SOCKET} is not a UNIX socket."
                break
            time.sleep(0.02)
        else:
            pytest.fail(f"Daemon did not bind {SOCKET} within 5 seconds.")

        client = subprocess.run(
            ["python3", CLIENT], capture_output=True, text=True, timeout=5
        )
        assert client.returncode == 0, (
            f"Provided client failed. stdout={client.stdout!r}, stderr={client.stderr!r}"
        )
        assert "Success" in client.stdout, f"Client did not report success: {client.stdout!r}"

        try:
            rc = proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pytest.fail("Daemon did not exit after serving the client.")
        assert rc == 0, f"Daemon exited with status {rc}."
        assert not os.path.lexists(SOCKET), "Daemon did not remove its UNIX socket during cleanup."
        assert not daemon_pids(), "edge_daemon process remains after the client request."
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        if os.path.lexists(SOCKET):
            os.unlink(SOCKET)


def test_sensor_log_created():
    assert os.path.isfile(LOG), f"Log file {LOG} is missing. Did you run the daemon and client script?"
    with open(LOG, "r") as f:
        content = f.read()
    assert "SENSOR_DATA_OK: 42.0" in content, (
        f"File {LOG} does not contain the expected sensor data. Found: {content}"
    )
    assert content.encode() == EXPECTED_LOG, f"Unexpected sensor log contents: {content!r}"


def test_backup_script_exists():
    assert os.path.isfile(SCRIPT), f"Backup script {SCRIPT} is missing."


def test_execute_backup_script_in_required_order():
    for path in BACKUPS:
        if os.path.lexists(path):
            os.remove(path)

    started = time.monotonic()
    run = subprocess.run(
        ["bash", "-x", SCRIPT], capture_output=True, text=True, timeout=15
    )
    elapsed = time.monotonic() - started
    trace = run.stderr
    assert run.returncode == 0, (
        f"Backup script failed with status {run.returncode}. stdout={run.stdout!r}, stderr={trace!r}"
    )

    events = []
    all_sleep_commands = []
    for raw in trace.splitlines():
        line = raw.lstrip("+ ")
        try:
            words = shlex.split(line)
        except ValueError:
            continue
        if not words:
            continue
        command = os.path.basename(words[0])
        if command == "sleep":
            all_sleep_commands.append(words)
            events.append(("sleep", words))
        elif command == "tar":
            for index, path in enumerate(BACKUPS, 1):
                if path in words or path in line:
                    assert LOG in words or LOG in line, f"Archive {path} was not made from {LOG}."
                    events.append((f"tar{index}", words))
                    break

    assert all_sleep_commands == [["sleep", "1"], ["sleep", "1"]], (
        "The executed script must perform exactly two `sleep 1` commands. "
        f"Observed: {all_sleep_commands!r}"
    )
    assert [event[0] for event in events] == ["tar1", "sleep", "tar2", "sleep", "tar3"], (
        "Backups and sleeps were not executed in the required order. "
        f"Observed trace events: {events!r}"
    )
    assert elapsed >= 1.8, f"Backup script completed too quickly ({elapsed:.3f}s) for two one-second sleeps."


def test_backups_created_and_valid():
    for b_path in BACKUPS:
        assert os.path.isfile(b_path), f"Backup archive {b_path} is missing."
        assert tarfile.is_tarfile(b_path), f"File {b_path} is not a valid tar archive."
        with tarfile.open(b_path, "r:gz") as tar:
            names = tar.getnames()
            assert any(name.endswith("sensor.log") for name in names), (
                f"Archive {b_path} does not contain 'sensor.log'."
            )
            matching = [m for m in tar.getmembers() if m.name.endswith("sensor.log")]
            assert matching, f"Archive {b_path} does not contain the sensor log."
            assert any(m.isfile() for m in matching), f"sensor.log in {b_path} is not a regular file."
            regular = next(m for m in matching if m.isfile())
            archived = tar.extractfile(regular)
            assert archived is not None
            assert archived.read() == EXPECTED_LOG, f"Archive {b_path} contains incorrect sensor data."


def test_backups_mtime():
    b1, b2, b3 = BACKUPS
    if os.path.isfile(b1) and os.path.isfile(b2) and os.path.isfile(b3):
        mtime1 = os.path.getmtime(b1)
        mtime2 = os.path.getmtime(b2)
        mtime3 = os.path.getmtime(b3)
        assert mtime2 > mtime1, "backup_2.tar.gz is not newer than backup_1.tar.gz. Did you sleep for 1 second?"
        assert mtime3 > mtime2, "backup_3.tar.gz is not newer than backup_2.tar.gz. Did you sleep for 1 second?"
        assert mtime2 - mtime1 >= 0.8, "First backup interval was shorter than one second."
        assert mtime3 - mtime2 >= 0.8, "Second backup interval was shorter than one second."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
