#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import stat
import subprocess
import time

ALERTER = "/home/user/alerter"
COLLECTOR = "/home/user/collector.sh"
SUPERVISOR = "/home/user/supervisor.sh"
READY = "/home/user/data/ready.flag"
HEARTBEAT = "/home/user/data/alerter.heartbeat"


def process_state(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            return f.read().split()[2]
    except (OSError, IndexError):
        return None


def live_pid(pid):
    return process_state(pid) not in (None, "Z")


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    except OSError:
        return []


def proc_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return None


def all_pids():
    return [int(x) for x in os.listdir("/proc") if x.isdigit()]


def matching_pids(kind):
    result = []
    for pid in all_pids():
        if not live_pid(pid):
            continue
        if kind == "alerter" and proc_exe(pid) == ALERTER:
            result.append(pid)
        elif kind == "collector" and COLLECTOR in proc_cmdline(pid):
            result.append(pid)
    return result


def descendants(root):
    found = set()
    changed = True
    while changed:
        changed = False
        for pid in all_pids():
            if pid in found or pid == root:
                continue
            try:
                with open(f"/proc/{pid}/status") as f:
                    ppid = next(int(line.split()[1]) for line in f if line.startswith("PPid:"))
            except (OSError, StopIteration, ValueError):
                continue
            if ppid == root or ppid in found:
                found.add(pid)
                changed = True
    return found


def kill_pid(pid):
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass


def stop_supervisor(pid):
    if pid and live_pid(pid):
        try:
            os.killpg(pid, signal.SIGTERM)
        except OSError:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        time.sleep(0.2)
        for child in descendants(pid):
            kill_pid(child)
        kill_pid(pid)
    for pid in matching_pids("alerter") + matching_pids("collector"):
        kill_pid(pid)
    time.sleep(0.2)


def wait_for(predicate, timeout, message):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    assert False, message


def read_recorded_supervisor_pid():
    with open("/home/user/supervisor.pid") as f:
        return int(f.read().strip())


def get_alerter_pids():
    """Original process-name check for running alerters."""
    try:
        output = subprocess.check_output(["pgrep", "-x", "alerter"]).decode().strip()
        return [int(x) for x in output.split() if x.isdigit() and live_pid(int(x))]
    except subprocess.CalledProcessError:
        return []


def test_alerter_compiled():
    path = ALERTER
    assert os.path.isfile(path), f"{path} binary is missing. Did you compile alerter.rs?"
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_directory_and_symlink():
    release_dir = "/home/user/data/releases/v1"
    symlink_path = "/home/user/data/active"
    assert os.path.isdir(release_dir), f"Directory {release_dir} is missing."
    assert os.path.islink(symlink_path), f"{symlink_path} is missing or is not a symlink."
    target = os.readlink(symlink_path)
    if not os.path.isabs(target):
        target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), target))
    assert target == release_dir, f"Symlink points to {target}, expected {release_dir}."


def test_supervisor_script():
    assert os.path.isfile(SUPERVISOR), f"{SUPERVISOR} is missing."
    assert os.access(SUPERVISOR, os.X_OK), f"{SUPERVISOR} is not executable."


def test_supervisor_running():
    pid_file = "/home/user/supervisor.pid"
    assert os.path.isfile(pid_file), f"{pid_file} is missing."
    with open(pid_file) as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer: '{pid_str}'"
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Supervisor process {pid} is not running."


def test_alerter_restart_policy():
    pids = get_alerter_pids()
    assert pids, "alerter process is not running."
    target_pid = pids[0]
    kill_pid(target_pid)
    time.sleep(2.5)
    new_pids = get_alerter_pids()
    assert new_pids, "Alerter was not restarted by the supervisor after being killed!"
    assert target_pid not in new_pids, "Alerter PID didn't change; kill failed or it wasn't actually restarted."


def test_artifact_and_dependency_behavior():
    # Stop the submitted instance so the executable and a fresh supervisor run
    # can be exercised without pre-existing processes or readiness state.
    old_pid = read_recorded_supervisor_pid()
    stop_supervisor(old_pid)

    active = "/home/user/data/active"
    backup = "/home/user/data/active.verifier-backup"
    for path in (READY, HEARTBEAT, backup):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    # Execute the submitted artifact against conditions derived from alerter.rs.
    missing_ready = subprocess.run([ALERTER], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, timeout=2)
    assert missing_ready.returncode != 0, "alerter did not reject a missing ready.flag"
    assert b"ready.flag not found" in missing_ready.stderr, \
        "alerter does not exhibit the required alerter.rs readiness behavior"

    os.rename(active, backup)
    try:
        open(READY, "w").close()
        missing_active = subprocess.run([ALERTER], stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, timeout=2)
        assert missing_active.returncode != 0, "alerter did not reject a missing active symlink"
        assert b"active does not exist" in missing_active.stderr, \
            "alerter does not exhibit the required alerter.rs active-path behavior"
    finally:
        os.rename(backup, active)

    try:
        os.unlink(HEARTBEAT)
    except FileNotFoundError:
        pass
    probe = subprocess.Popen([ALERTER], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for(lambda: os.path.isfile(HEARTBEAT), 2,
                 "compiled alerter did not create its heartbeat")
        with open(HEARTBEAT) as f:
            assert f.read() == "alive", "alerter heartbeat has the wrong contents"
    finally:
        kill_pid(probe.pid)
        try:
            probe.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass

    # Replace the collector temporarily with a gated collector. This proves that
    # supervisor.sh actually launches the required path and cannot start alerter
    # until that collector creates ready.flag.
    with open(COLLECTOR, "rb") as f:
        collector_bytes = f.read()
    collector_mode = stat.S_IMODE(os.stat(COLLECTOR).st_mode)
    marker = "/tmp/verifier-collector-started"
    gate = "/tmp/verifier-release-collector"
    for path in (marker, gate, READY, HEARTBEAT):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    gated = b'''#!/bin/bash
rm -f /home/user/data/ready.flag
touch /tmp/verifier-collector-started
while [ ! -e /tmp/verifier-release-collector ]; do sleep 0.05; done
touch /home/user/data/ready.flag
while true; do sleep 60; done
'''
    test_supervisor = None
    try:
        with open(COLLECTOR, "wb") as f:
            f.write(gated)
        os.chmod(COLLECTOR, 0o755)

        test_supervisor = subprocess.Popen([SUPERVISOR], stdout=subprocess.DEVNULL,
                                           stderr=subprocess.DEVNULL,
                                           start_new_session=True)
        wait_for(lambda: os.path.exists(marker), 2,
                 "supervisor did not start /home/user/collector.sh")
        assert matching_pids("collector"), "collector.sh is not running"

        # Keep readiness gated long enough to catch supervisors that start the
        # alerter immediately or merely rely on a manually pre-created flag.
        deadline = time.monotonic() + 1.0
        while time.monotonic() < deadline:
            assert not os.path.exists(READY), "ready.flag appeared before the collector was released"
            assert not matching_pids("alerter"), \
                "supervisor started alerter before collector-created ready.flag existed"
            time.sleep(0.05)

        open(gate, "w").close()
        wait_for(lambda: os.path.exists(READY), 2,
                 "the started collector did not create ready.flag")
        first = wait_for(lambda: matching_pids("alerter"), 2,
                         "supervisor did not start /home/user/alerter after readiness")
        wait_for(lambda: os.path.isfile(HEARTBEAT), 2,
                 "supervised alerter did not produce its heartbeat")

        target = first[0]
        kill_pid(target)
        restarted = wait_for(lambda: [p for p in matching_pids("alerter") if p != target],
                             2.5, "supervisor did not restart the actual alerter executable")
        assert restarted
    finally:
        if test_supervisor is not None:
            stop_supervisor(test_supervisor.pid)
        with open(COLLECTOR, "wb") as f:
            f.write(collector_bytes)
        os.chmod(COLLECTOR, collector_mode)
        for path in (marker, gate, READY, HEARTBEAT):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

    # Restore the required final state using the submitted supervisor and the
    # original collector, and leave that supervisor running.
    final_supervisor = subprocess.Popen([SUPERVISOR], stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL,
                                        start_new_session=True)
    with open("/home/user/supervisor.pid", "w") as f:
        f.write(str(final_supervisor.pid))
    wait_for(lambda: matching_pids("collector"), 2,
             "restored supervisor did not start the original collector")
    wait_for(lambda: os.path.exists(READY), 6,
             "original collector did not create ready.flag")
    wait_for(lambda: matching_pids("alerter"), 3,
             "restored supervisor did not start alerter")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
