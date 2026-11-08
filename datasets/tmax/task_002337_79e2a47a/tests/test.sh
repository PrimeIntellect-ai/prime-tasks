#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_final_state.py
import glob
import json
import os
import signal
import subprocess
import time

import pytest

SUPERVISOR = "/home/user/supervisor.py"
SERVICE_A = "/home/user/service_a.py"
SERVICE_B = "/home/user/service_b.py"
STATUS = "/home/user/monitor_status.json"
LOG_DIR = "/home/user/logs"
LOG_FILE = os.path.join(LOG_DIR, "services.log")


def proc_info(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        with open(f"/proc/{pid}/stat") as f:
            stat = f.read().split()
        return argv, int(stat[3]), stat[2]
    except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
        return None


def all_processes():
    result = {}
    for entry in os.listdir("/proc"):
        if entry.isdigit():
            info = proc_info(int(entry))
            if info is not None:
                result[int(entry)] = info
    return result


def exact_python_processes(script):
    matches = []
    for pid, (argv, ppid, state) in all_processes().items():
        if state != "Z" and len(argv) == 2 and argv[0] == "/usr/bin/python3" and argv[1] == script:
            matches.append((pid, ppid))
    return matches


def child_for(supervisor_pid, script):
    for pid, ppid in exact_python_processes(script):
        if ppid == supervisor_pid:
            return pid
    return None


def read_environ(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    return dict(x.decode(errors="replace").split("=", 1) for x in entries if b"=" in x)


def read_json_retry(path=STATUS, timeout=2.0):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        try:
            with open(path) as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError, OSError) as exc:
            last = exc
            time.sleep(0.03)
    raise AssertionError(f"Could not read valid JSON from {path}: {last}")


def wait_until(fn, timeout=6.0, interval=0.05):
    end = time.time() + timeout
    while time.time() < end:
        value = fn()
        if value:
            return value
        time.sleep(interval)
    return None


def kill_matching_processes():
    me = os.getpid()
    targets = []
    for pid, (argv, _ppid, _state) in all_processes().items():
        if pid == me:
            continue
        joined = "\0".join(argv)
        if any(path in joined for path in (SUPERVISOR, SERVICE_A, SERVICE_B)):
            targets.append(pid)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in targets:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.3)


def assert_status_shape(data):
    assert set(data) == {"service_a", "service_b", "restarts"}, "Status JSON must have exactly the required keys."
    assert data["service_a"] == "running"
    assert data["service_b"] == "running"
    assert isinstance(data["restarts"], int) and not isinstance(data["restarts"], bool)


def test_complete_supervisor_behavior():
    # Preserve the original existence and content assertions.
    env_file = "/home/user/.service_env"
    assert os.path.isfile(env_file), f"Environment file {env_file} does not exist."
    with open(env_file) as f:
        content = f.read()
    assert "API_KEY=sre_monitor_99" in content
    assert "SERVICE_B_PORT=9090" in content
    assert os.path.isfile(SUPERVISOR), "supervisor.py does not exist."

    # Verify the requested background process and its real, direct children rather
    # than accepting arbitrary command lines found by pgrep.
    supervisors = exact_python_processes(SUPERVISOR)
    assert supervisors, "supervisor.py is not running as /usr/bin/python3 in the background."
    live = None
    for supervisor_pid, _ in supervisors:
        a_pid = child_for(supervisor_pid, SERVICE_A)
        b_pid = child_for(supervisor_pid, SERVICE_B)
        if a_pid and b_pid:
            live = (supervisor_pid, a_pid, b_pid)
            break
    assert live, "The running supervisor does not have both specified Python services as direct children."
    supervisor_pid, a_pid, b_pid = live
    for pid in (a_pid, b_pid):
        env = read_environ(pid)
        assert env.get("API_KEY") == "sre_monitor_99"
        assert env.get("SERVICE_B_PORT") == "9090"

    data = read_json_retry()
    assert_status_shape(data)
    initial_restarts = data["restarts"]

    assert os.path.isdir(LOG_DIR)
    assert os.path.isfile(LOG_FILE)
    time.sleep(2)
    rotated = LOG_FILE + ".1"
    assert os.path.isfile(rotated), "services.log.1 was not created."
    assert 500 <= os.path.getsize(rotated) <= 2048

    # Preserve the original live restart assertion, but target the actual child.
    os.kill(a_pid, signal.SIGKILL)
    new_a = wait_until(lambda: child_for(supervisor_pid, SERVICE_A), timeout=4)
    assert new_a and new_a != a_pid, "service_a.py was not restarted by its supervisor."
    restarted_data = wait_until(
        lambda: (lambda d: d if d.get("restarts", initial_restarts) > initial_restarts else None)(read_json_retry()),
        timeout=4,
    )
    assert restarted_data, "Restarts counter was not incremented after service_a was killed."
    assert restarted_data["service_a"] == "running"

    # Re-execute the submitted artifact against instrumented versions of the exact
    # service paths. This proves child identity/environment, both-stream capture,
    # one-second status writes, restart behavior, and the configured rotation.
    originals = {}
    modes = {}
    for path in (SERVICE_A, SERVICE_B):
        with open(path, "rb") as f:
            originals[path] = f.read()
        modes[path] = os.stat(path).st_mode

    probe_template = '''import os, sys, time
name = {name!r}
while True:
    print(name + "_OUT:" + "O" * 150, flush=True)
    print(name + "_ERR:" + "E" * 150, file=sys.stderr, flush=True)
    time.sleep(0.08)
'''

    launched = None
    try:
        kill_matching_processes()
        for path, name in ((SERVICE_A, "A"), (SERVICE_B, "B")):
            with open(path, "w") as f:
                f.write(probe_template.format(name=name))
            os.chmod(path, 0o755)

        os.makedirs(LOG_DIR, exist_ok=True)
        for path in glob.glob(os.path.join(LOG_DIR, "services.log*")):
            os.remove(path)
        try:
            os.remove(STATUS)
        except FileNotFoundError:
            pass

        clean_env = os.environ.copy()
        clean_env.pop("API_KEY", None)
        clean_env.pop("SERVICE_B_PORT", None)
        launched = subprocess.Popen(
            ["/usr/bin/python3", SUPERVISOR],
            cwd="/home/user",
            env=clean_env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        def find_managed_set():
            for spid, _ in exact_python_processes(SUPERVISOR):
                apid = child_for(spid, SERVICE_A)
                bpid = child_for(spid, SERVICE_B)
                if apid and bpid:
                    return spid, apid, bpid
            return None

        managed = wait_until(find_managed_set, timeout=6)
        assert managed, "Executing supervisor.py did not spawn both specified service commands."
        spid, apid, bpid = managed
        for pid in (apid, bpid):
            env = read_environ(pid)
            assert env.get("API_KEY") == "sre_monitor_99"
            assert env.get("SERVICE_B_PORT") == "9090"

        first_status = read_json_retry(timeout=4)
        assert_status_shape(first_status)

        # Record actual status-file writes. A compliant supervisor rewrites it on
        # each approximately one-second polling pass.
        mtimes = [os.stat(STATUS).st_mtime_ns]
        deadline = time.monotonic() + 4.2
        while time.monotonic() < deadline and len(mtimes) < 5:
            current = os.stat(STATUS).st_mtime_ns
            if current != mtimes[-1]:
                mtimes.append(current)
            time.sleep(0.03)
        assert len(mtimes) >= 4, "monitor_status.json was not written on repeated polling passes."
        intervals = [(b - a) / 1_000_000_000 for a, b in zip(mtimes, mtimes[1:])]
        assert all(0.65 <= d <= 1.5 for d in intervals[:3]), f"Status polling is not approximately once per second: {intervals}"

        before = read_json_retry()["restarts"]
        os.kill(apid, signal.SIGKILL)
        replacement = wait_until(lambda: child_for(spid, SERVICE_A), timeout=4)
        assert replacement and replacement != apid
        after = wait_until(
            lambda: (lambda d: d if d.get("restarts", before) > before else None)(read_json_retry()),
            timeout=4,
        )
        assert after, "Dynamically executed supervisor did not increment its global restart count."
        assert after["service_a"] == "running"

        time.sleep(2)
        paths = sorted(glob.glob(os.path.join(LOG_DIR, "services.log*")))
        names = {os.path.basename(p) for p in paths}
        assert {"services.log", "services.log.1", "services.log.2", "services.log.3"}.issubset(names)
        assert not any(name.startswith("services.log.") and name.split(".")[-1].isdigit() and int(name.split(".")[-1]) > 3 for name in names), "More than three log backups were retained."
        for path in paths:
            if os.path.basename(path) in {"services.log", "services.log.1", "services.log.2", "services.log.3"}:
                assert os.path.getsize(path) <= 1024, f"{path} exceeded the required 1024-byte maximum."
        backup_sizes = [os.path.getsize(LOG_FILE + f".{n}") for n in (1, 2, 3)]
        assert max(backup_sizes) >= 700, f"Backups are inconsistent with a 1024-byte rotation threshold: {backup_sizes}"
        combined = b"".join(open(p, "rb").read() for p in paths if os.path.basename(p) in {"services.log", "services.log.1", "services.log.2", "services.log.3"})
        for token in (b"A_OUT:", b"A_ERR:", b"B_OUT:", b"B_ERR:"):
            assert token in combined, f"Missing captured stream marker {token!r} from rotated logs."
    finally:
        for path, body in originals.items():
            with open(path, "wb") as f:
                f.write(body)
            os.chmod(path, modes[path])

    # Leave the submitted supervisor running with the supplied services, as the
    # instruction requires. Killing the probe children forces them to be reloaded
    # from the restored service files.
    if 'spid' in locals():
        for pid in (child_for(spid, SERVICE_A), child_for(spid, SERVICE_B)):
            if pid:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        assert wait_until(lambda: child_for(spid, SERVICE_A), timeout=4)
        assert wait_until(lambda: child_for(spid, SERVICE_B), timeout=4)
PYTEST

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
