#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import textwrap
import time
import uuid
from pathlib import Path

import pytest

MANAGER = "/home/user/restore_manager.py"
DB_MOCK = "/home/user/db_mock.py"
RESTORE = "/home/user/run_restore.py"
SOCKET = "/home/user/db_ready.sock"
LOG = "/home/user/restore_success.log"
EXPECTED = "RESTORE_COMPLETED_SUCCESSFULLY_99283"


def kill_db_mocks():
    result = subprocess.run(
        ["pgrep", "-f", "/home/user/db_mock.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    for value in result.stdout.split():
        try:
            pid = int(value)
            if pid != os.getpid():
                os.kill(pid, signal.SIGTERM)
        except (ValueError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.2)


def run_manager(timeout=15):
    return subprocess.run(
        ["python3", MANAGER],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )


def test_restore_manager_exists():
    path = MANAGER
    assert os.path.exists(path), f"Missing file: {path}"
    assert os.path.isfile(path), f"Not a file: {path}"


def test_restore_manager_runs_successfully():
    kill_db_mocks()
    for path in (SOCKET, LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = run_manager()
    assert result.returncode == 0, (
        f"restore_manager.py exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_restore_success_log_exists_and_content():
    path = LOG
    assert os.path.exists(path), f"Missing file: {path}. The script did not generate the log file."
    assert os.path.isfile(path), f"Not a file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    expected = EXPECTED
    assert content == expected, f"Incorrect content in {path}. Expected '{expected}', got '{content}'"


def test_manager_actually_orchestrates_processes():
    nonce = uuid.uuid4().hex
    probe_dir = Path("/tmp") / f"restore_manager_probe_{nonce}"
    probe_dir.mkdir()
    db_started = str(probe_dir / "db_started")
    db_ready = str(probe_dir / "db_ready")
    db_terminated = str(probe_dir / "db_terminated")
    restore_called = str(probe_dir / "restore_called")
    payload = f"PROBE_RESTORE_SUCCESS_{nonce}\nSECOND_LINE_{nonce}\n".encode()

    db_path = Path(DB_MOCK)
    restore_path = Path(RESTORE)
    old_db = db_path.read_bytes()
    old_restore = restore_path.read_bytes()
    old_db_mode = db_path.stat().st_mode
    old_restore_mode = restore_path.stat().st_mode

    probe_db = textwrap.dedent(f"""\
        #!/usr/bin/env python3
        import os
        import signal
        import sys
        import time

        socket_path = {SOCKET!r}
        started_path = {db_started!r}
        ready_path = {db_ready!r}
        terminated_path = {db_terminated!r}

        def terminate(signum, frame):
            with open(terminated_path, "w") as f:
                f.write(str(os.getpid()))
            time.sleep(1.0)
            try:
                os.remove(socket_path)
            except FileNotFoundError:
                pass
            sys.exit(0)

        signal.signal(signal.SIGTERM, terminate)
        signal.signal(signal.SIGINT, terminate)
        with open(started_path, "w") as f:
            f.write(str(os.getpid()))
        time.sleep(1.3)
        with open(socket_path, "w") as f:
            f.write({('READY_' + nonce)!r})
        with open(ready_path, "w") as f:
            f.write("ready")
        while True:
            time.sleep(0.1)
    """)

    probe_restore = textwrap.dedent(f"""\
        #!/usr/bin/env python3
        import os
        import sys

        socket_path = {SOCKET!r}
        started_path = {db_started!r}
        called_path = {restore_called!r}
        with open(called_path, "a") as f:
            f.write("called\\n")
        try:
            with open(socket_path, "r") as f:
                state = f.read()
            with open(started_path, "r") as f:
                db_pid = int(f.read())
            os.kill(db_pid, 0)
        except Exception as exc:
            print(f"database unavailable: {{exc}}", file=sys.stderr)
            sys.exit(41)
        if state != {('READY_' + nonce)!r}:
            print("stale readiness file", file=sys.stderr)
            sys.exit(42)
        sys.stdout.buffer.write({payload!r})
    """)

    probe_pid = None
    try:
        kill_db_mocks()
        Path(SOCKET).write_text("STALE_SOCKET_FROM_CRASH")
        try:
            os.remove(LOG)
        except FileNotFoundError:
            pass

        db_path.write_text(probe_db)
        restore_path.write_text(probe_restore)
        os.chmod(DB_MOCK, 0o755)
        os.chmod(RESTORE, 0o755)

        started = time.monotonic()
        result = run_manager()
        elapsed = time.monotonic() - started

        assert result.returncode == 0, (
            f"Manager failed against delayed probe services: stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
        assert Path(db_started).is_file(), "The manager did not start db_mock.py"
        assert Path(db_ready).is_file(), "db_mock.py never reached readiness"
        assert Path(restore_called).is_file(), "The manager did not invoke run_restore.py"
        assert Path(restore_called).read_text().splitlines() == ["called"], "run_restore.py was not invoked exactly once"
        assert Path(LOG).is_file(), "The manager did not create restore_success.log"
        assert Path(LOG).read_bytes() == payload, "Restore stdout was not captured exactly as-is"
        assert Path(db_terminated).is_file(), "The manager did not send SIGTERM to db_mock.py"
        assert elapsed >= 2.0, "The manager returned without waiting for readiness and clean database shutdown"
        assert not Path(SOCKET).exists(), "The readiness socket remained after manager completion"

        probe_pid = int(Path(db_started).read_text())
        with pytest.raises(ProcessLookupError):
            os.kill(probe_pid, 0)
    finally:
        if probe_pid is None and Path(db_started).exists():
            try:
                probe_pid = int(Path(db_started).read_text())
            except ValueError:
                probe_pid = None
        if probe_pid is not None:
            try:
                os.kill(probe_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        kill_db_mocks()
        db_path.write_bytes(old_db)
        restore_path.write_bytes(old_restore)
        os.chmod(DB_MOCK, old_db_mode)
        os.chmod(RESTORE, old_restore_mode)
        try:
            os.remove(SOCKET)
        except FileNotFoundError:
            pass

        # Restore the required final state using the original supplied programs.
        final_result = run_manager()
        if final_result.returncode != 0:
            pytest.fail(
                f"Manager failed after restoring original programs: "
                f"stdout={final_result.stdout!r}, stderr={final_result.stderr!r}"
            )


def test_db_mock_not_running():
    try:
        output = subprocess.check_output(["pgrep", "-f", "db_mock.py"]).decode("utf-8")
        running = bool(output.strip())
    except subprocess.CalledProcessError:
        running = False

    assert not running, "db_mock.py process is still running. It should have been terminated cleanly."


def test_socket_does_not_exist():
    path = SOCKET
    assert not os.path.exists(path), f"Socket file still exists: {path}. The db_mock.py process was not cleanly terminated."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
