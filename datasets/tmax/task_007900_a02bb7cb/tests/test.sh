#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

MONITOR = "/home/user/monitor.py"
START = Path("/home/user/legacy_service/start.sh")
BACKUP = Path("/tmp/original_start.sh")
LOG = Path("/home/user/monitoring.log")
CALLS = Path("/tmp/verifier_start_calls")
ACCEPTS = Path("/tmp/verifier_accepts")
PIDFILE = Path("/tmp/verifier_server.pid")


def kill_matching(pattern):
    subprocess.run(["pkill", "-f", pattern], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)


def stop_server():
    if PIDFILE.exists():
        try:
            os.kill(int(PIDFILE.read_text().strip()), signal.SIGTERM)
        except (ValueError, ProcessLookupError, PermissionError):
            pass
        time.sleep(0.15)
        PIDFILE.unlink(missing_ok=True)


def start_server():
    return subprocess.Popen(
        [sys.executable, "/tmp/verifier_server.py"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def read_times(path):
    if not path.exists():
        return []
    result = []
    for line in path.read_text().splitlines():
        try:
            result.append(float(line.strip()))
        except ValueError:
            pass
    return result


def wait_for(predicate, timeout, message):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(message)


def call_count():
    return len(CALLS.read_text().splitlines()) if CALLS.exists() else 0


def write_test_files():
    Path("/tmp/verifier_server.py").write_text(r'''import os
import signal
import socket
import time

running = True
def stop(*args):
    global running
    running = False

signal.signal(signal.SIGTERM, stop)
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8888))
s.listen(20)
s.settimeout(0.2)
open("/tmp/verifier_server.pid", "w").write(str(os.getpid()))
try:
    while running:
        try:
            conn, _ = s.accept()
            conn.close()
            with open("/tmp/verifier_accepts", "a") as f:
                f.write(str(time.monotonic()) + "\\n")
                f.flush()
        except socket.timeout:
            pass
finally:
    s.close()
''')

    START.write_text(r'''#!/bin/bash
date +%s >> /tmp/verifier_start_calls
(
  sleep 4
  python3 /tmp/verifier_server.py >/dev/null 2>&1
) >/dev/null 2>&1 &
exit 0
''')
    START.chmod(0o755)


def check_timeout_and_poll_interval():
    fake_dir = Path("/tmp/verifier_fake_socket")
    fake_dir.mkdir(exist_ok=True)
    trace = Path("/tmp/verifier_socket_trace")
    trace.unlink(missing_ok=True)
    CALLS.unlink(missing_ok=True)

    (fake_dir / "sitecustomize.py").write_text(r'''import socket as _socket
import time

_trace = "/tmp/verifier_socket_trace"
def emit(kind, ident="-", value="-"):
    with open(_trace, "a") as f:
        f.write("%s %.6f %s %s\\n" % (kind, time.monotonic(), ident, value))
        f.flush()

_RealTimeout = _socket.timeout
_next = [0]
class FakeSocket:
    def __init__(self, *args, **kwargs):
        _next[0] += 1
        self.ident = str(_next[0])
        self.timeout = None
        emit("NEW", self.ident)
    def settimeout(self, value):
        self.timeout = value
        emit("TIMEOUT", self.ident, repr(value))
    def connect(self, address):
        emit("ATTEMPT", self.ident, repr(self.timeout))
        raise _RealTimeout("controlled timeout")
    def connect_ex(self, address):
        emit("ATTEMPT", self.ident, repr(self.timeout))
        return 110
    def close(self):
        pass
    def __enter__(self):
        return self
    def __exit__(self, *args):
        self.close()

_socket.socket = FakeSocket
def fake_create_connection(address, timeout=_socket._GLOBAL_DEFAULT_TIMEOUT, source_address=None, all_errors=False):
    _next[0] += 1
    ident = str(_next[0])
    shown = None if timeout is _socket._GLOBAL_DEFAULT_TIMEOUT else timeout
    emit("NEW", ident)
    emit("TIMEOUT", ident, repr(shown))
    emit("ATTEMPT", ident, repr(shown))
    raise _RealTimeout("controlled timeout")
_socket.create_connection = fake_create_connection
''')

    env = os.environ.copy()
    env["PYTHONPATH"] = str(fake_dir)
    proc = subprocess.Popen(
        [sys.executable, MONITOR], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        wait_for(lambda: len([x for x in trace.read_text().splitlines()
                              if x.startswith("ATTEMPT ")]) >= 3
                 if trace.exists() else False,
                 5.5, "monitor did not make three timed connection attempts")
        wait_for(lambda: call_count() >= 1, 2.0,
                 "monitor did not execute start.sh after three failures")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()

    attempts = []
    for line in trace.read_text().splitlines():
        parts = line.split(maxsplit=3)
        if parts[0] == "ATTEMPT":
            attempts.append((float(parts[1]), parts[3]))
    assert len(attempts) >= 3
    for _, timeout_value in attempts[:3]:
        assert timeout_value in ("1", "1.0"), \
            f"connection attempt did not use the required 1-second timeout: {timeout_value}"
    gaps = [attempts[i + 1][0] - attempts[i][0] for i in range(2)]
    assert all(0.70 <= gap <= 1.50 for gap in gaps), \
        f"connection attempts were not made at approximately 1-second intervals: {gaps}"


def test_monitor_behavior_and_prepare_final_state():
    assert os.path.isfile(MONITOR), "The script /home/user/monitor.py does not exist."

    kill_matching("/home/user/monitor.py")
    kill_matching("python3 /home/user/legacy_service/app.py")
    stop_server()
    BACKUP.write_bytes(START.read_bytes())
    write_test_files()
    LOG.unlink(missing_ok=True)
    CALLS.unlink(missing_ok=True)
    ACCEPTS.unlink(missing_ok=True)

    monitor = None
    server = None
    try:
        check_timeout_and_poll_interval()
        CALLS.unlink(missing_ok=True)
        LOG.unlink(missing_ok=True)
        ACCEPTS.unlink(missing_ok=True)
        stop_server()

        server = start_server()
        wait_for(lambda: PIDFILE.exists(), 2, "controlled service did not start")
        monitor = subprocess.Popen(
            [sys.executable, MONITOR], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        wait_for(lambda: len(read_times(ACCEPTS)) >= 3, 5,
                 "monitor did not continuously poll a healthy service")
        healthy = read_times(ACCEPTS)[:3]
        healthy_gaps = [healthy[i + 1] - healthy[i] for i in range(2)]
        assert all(0.70 <= gap <= 1.50 for gap in healthy_gaps), \
            f"healthy-service polling was not approximately once per second: {healthy_gaps}"
        assert call_count() == 0, "monitor blindly ran start.sh while service was healthy"
        assert not LOG.exists() or not LOG.read_text().strip(), \
            "monitor emitted a failure alert while service was healthy"

        # Two consecutive failures followed by success must reset the counter.
        stop_server()
        if server is not None:
            server.wait(timeout=2)
        time.sleep(2.20)
        before_reset = len(read_times(ACCEPTS))
        server = start_server()
        wait_for(lambda: len(read_times(ACCEPTS)) > before_reset, 2,
                 "monitor did not resume after a short outage")
        assert call_count() == 0, "monitor restarted before three consecutive failures"
        assert not LOG.exists() or not LOG.read_text().strip(), \
            "monitor alerted before three consecutive failures"

        # After a successful reset, a fresh run of three failures must restart once.
        time.sleep(0.10)
        last_success = read_times(ACCEPTS)[-1]
        stop_server()
        if server is not None:
            server.wait(timeout=2)
        server = None
        wait_for(lambda: call_count() >= 1, 5.5,
                 "monitor did not restart after three consecutive failures")
        restart_time = time.monotonic()
        assert restart_time - last_success >= 2.35, \
            "monitor restarted before observing three consecutive failed polls"

        assert LOG.exists(), "monitor did not append an alert"
        lines = LOG.read_text().splitlines()
        assert len(lines) == 1, f"expected one alert for one outage, got {lines}"
        match = re.fullmatch(r"ALERT: Service failure detected at (\d+)", lines[0])
        assert match, "alert does not have the required exact format"
        assert abs(int(match.group(1)) - int(time.time())) <= 10, \
            "alert timestamp is not the current integer Unix time"

        # start.sh deliberately takes four seconds to restore service. A supervisor
        # must wait for recovery rather than issuing duplicate alerts/restarts.
        accepted_before_recovery = len(read_times(ACCEPTS))
        wait_for(lambda: len(read_times(ACCEPTS)) > accepted_before_recovery, 6,
                 "monitor did not wait for and detect service recovery")
        time.sleep(0.35)
        assert call_count() == 1, \
            "monitor invoked start.sh more than once while waiting for recovery"
        assert len(LOG.read_text().splitlines()) == 1, \
            "monitor emitted duplicate alerts while waiting for recovery"
        wait_for(lambda: len(read_times(ACCEPTS)) >= accepted_before_recovery + 2, 2,
                 "monitor did not resume standard polling after recovery")
        recovered = read_times(ACCEPTS)[-2:]
        assert 0.70 <= recovered[1] - recovered[0] <= 1.50, \
            "monitor did not resume its 1-second polling loop after recovery"
        assert monitor.poll() is None, "monitor crashed instead of running continuously"
    finally:
        if monitor is not None and monitor.poll() is None:
            monitor.terminate()
            try:
                monitor.wait(timeout=2)
            except subprocess.TimeoutExpired:
                monitor.kill()
        stop_server()
        kill_matching("/tmp/verifier_server.py")
        if BACKUP.exists():
            START.write_bytes(BACKUP.read_bytes())
            START.chmod(0o755)

    # Recreate the requested final state using the real legacy service and the
    # submitted monitor. The behavioral alert remains as evidence of recovery.
    subprocess.run([str(START)], check=True)
    final_monitor = subprocess.Popen(
        [sys.executable, MONITOR], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    time.sleep(0.25)
    assert final_monitor.poll() is None, "monitor.py is not running in the background"


def test_monitor_script_exists():
    assert os.path.isfile("/home/user/monitor.py"), "The script /home/user/monitor.py does not exist."


def test_monitor_is_running():
    try:
        output = subprocess.check_output(["pgrep", "-f", "monitor.py"]).decode("utf-8")
        assert len(output.strip()) > 0, "monitor.py is not running in the background."
    except subprocess.CalledProcessError:
        assert False, "monitor.py is not running in the background."


def test_monitoring_log_format():
    log_path = "/home/user/monitoring.log"
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist. Did the monitor detect a crash?"
    with open(log_path, "r") as f:
        content = f.read().strip().splitlines()
    assert len(content) > 0, f"The log file {log_path} is empty."
    pattern = re.compile(r"^ALERT: Service failure detected at \d+$")
    match_found = any(pattern.match(line) for line in content)
    assert match_found, f"No line in {log_path} matches the required format 'ALERT: Service failure detected at <UNIX_TIMESTAMP>'."


def test_service_is_running_and_listening():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        result = s.connect_ex(("127.0.0.1", 8888))
        assert result == 0, "The service is not listening on 127.0.0.1:8888. The monitor may have failed to restart it."
    finally:
        s.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
