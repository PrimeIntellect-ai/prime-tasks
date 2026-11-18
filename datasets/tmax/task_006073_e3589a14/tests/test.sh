#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import subprocess
import tempfile
import time

CONFIG = "/home/user/config.env"
SOURCE = "/home/user/heartbeat.c"
BINARY = "/home/user/heartbeat"
SVC = "/home/user/svc.sh"
LOG = "/home/user/heartbeat.log"
PIDFILE = "/home/user/heartbeat.pid"


def wait_for(predicate, timeout=4.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


def process_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def clean_service():
    if os.path.exists(PIDFILE):
        try:
            with open(PIDFILE) as f:
                pid = int(f.read().strip())
            if process_exists(pid):
                os.kill(pid, signal.SIGKILL)
                wait_for(lambda: not process_exists(pid), 2.0)
        except Exception:
            pass
        try:
            os.remove(PIDFILE)
        except FileNotFoundError:
            pass


def test_config_env():
    assert os.path.isfile(CONFIG), f"{CONFIG} does not exist."
    with open(CONFIG) as f:
        content = f.read().strip()
    assert content == "STATUS=RUNNING", f"Expected STATUS=RUNNING in {CONFIG}, got {content}"


def test_heartbeat_c_exists():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."


def test_heartbeat_binary():
    assert os.path.isfile(BINARY), f"{BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable."


def test_svc_sh_exists_and_executable():
    assert os.path.isfile(SVC), f"{SVC} does not exist."
    assert os.access(SVC, os.X_OK), f"{SVC} is not executable."


def exercise_daemon(executable, ping_count):
    with open(CONFIG, "w") as f:
        f.write("STATUS=RUNNING\n")
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(
        [executable], stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        time.sleep(0.3)
        assert proc.poll() is None, "Daemon exited despite valid configuration."
        for _ in range(ping_count):
            os.kill(proc.pid, signal.SIGUSR1)
            time.sleep(0.15)
        expected_ping_log = "Heartbeat received\n" * ping_count
        assert wait_for(
            lambda: os.path.exists(LOG) and open(LOG).read() == expected_ping_log
        ), "SIGUSR1 did not produce the exact required log output."

        os.kill(proc.pid, signal.SIGTERM)
        assert proc.wait(timeout=4) == 0, "SIGTERM did not cause a graceful exit with code 0."
        with open(LOG) as f:
            content = f.read()
        assert content == expected_ping_log + "Shutting down\n", \
            f"Daemon log output was not exact: {content!r}"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)


def assert_rejects_bad_config(executable, content):
    if content is None:
        try:
            os.remove(CONFIG)
        except FileNotFoundError:
            pass
    else:
        with open(CONFIG, "w") as f:
            f.write(content)
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [executable], stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2
    )
    assert result.returncode == 1, \
        f"Daemon returned {result.returncode} instead of 1 for invalid configuration."
    assert not os.path.exists(LOG), "Daemon logged or ran despite invalid configuration."


def test_source_compiles_and_daemons_are_functional():
    try:
        with tempfile.TemporaryDirectory() as td:
            rebuilt = os.path.join(td, "heartbeat-from-source")
            compile_result = subprocess.run(
                ["gcc", SOURCE, "-o", rebuilt],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            assert compile_result.returncode == 0, \
                f"heartbeat.c did not compile:\n{compile_result.stderr}"

            # Independently exercise both the submitted executable and an executable
            # freshly compiled from the submitted C source.
            exercise_daemon(BINARY, 2 + secrets.randbelow(3))
            exercise_daemon(rebuilt, 2 + secrets.randbelow(3))

            for executable in (BINARY, rebuilt):
                assert_rejects_bad_config(executable, "STATUS=STOPPED\n")
                assert_rejects_bad_config(executable, None)
    finally:
        with open(CONFIG, "w") as f:
            f.write("STATUS=RUNNING\n")
        try:
            os.remove(LOG)
        except FileNotFoundError:
            pass


def test_argument_validation():
    for args in ([], ["invalid"], ["start", "extra"]):
        result = subprocess.run(
            [SVC] + args, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3
        )
        assert result.returncode != 0, f"svc.sh accepted invalid arguments: {args!r}"


def test_lifecycle():
    clean_service()
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass

    pid = None
    try:
        # Exercise multiple independently chosen lifecycle sequences rather than one
        # fixed start/ping/stop transcript.
        for cycle in range(2):
            try:
                os.remove(LOG)
            except FileNotFoundError:
                pass

            result = subprocess.run(
                [SVC, "start"], stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4
            )
            assert result.returncode == 0, f"svc.sh start failed with code {result.returncode}"
            assert wait_for(lambda: os.path.isfile(PIDFILE)), \
                f"PID file {PIDFILE} was not created after start."

            with open(PIDFILE) as f:
                pid_str = f.read().strip()
            assert pid_str.isdigit(), f"PID file does not contain a valid PID: {pid_str}"
            pid = int(pid_str)
            assert process_exists(pid), f"Daemon process with PID {pid} is not running."

            proc_exe = f"/proc/{pid}/exe"
            assert os.path.exists(proc_exe), f"Daemon process {pid} has no executable."
            assert os.path.samefile(proc_exe, BINARY), \
                "svc.sh did not start /home/user/heartbeat as the recorded process."

            ping_count = 2 + secrets.randbelow(5)
            for _ in range(ping_count):
                result = subprocess.run(
                    [SVC, "ping"], stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4
                )
                assert result.returncode == 0, f"svc.sh ping failed with code {result.returncode}"
                time.sleep(0.12)

            expected = "Heartbeat received\n" * ping_count
            assert wait_for(lambda: os.path.isfile(LOG) and open(LOG).read() == expected), \
                "Lifecycle pings did not produce the exact required log."

            result = subprocess.run(
                [SVC, "stop"], stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=6
            )
            assert result.returncode == 0, f"svc.sh stop failed with code {result.returncode}"
            assert wait_for(lambda: not process_exists(pid)), \
                f"Daemon process {pid} did not terminate after stop."
            assert not os.path.exists(PIDFILE), f"PID file {PIDFILE} was not removed after stop."

            with open(LOG) as f:
                content = f.read()
            assert content == expected + "Shutting down\n", \
                f"Lifecycle log output was not exact: {content!r}"
            pid = None
    finally:
        if pid is not None and process_exists(pid):
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        clean_service()
        with open(CONFIG, "w") as f:
            f.write("STATUS=RUNNING\n")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
