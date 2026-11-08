#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import select
import secrets
import signal
import stat
import subprocess
import time
import pytest

HOME = "/home/user"
LOG_DIR = f"{HOME}/logs"


def proc_records():
    records = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                argv = [x.decode("utf-8", "replace") for x in f.read().split(b"\0") if x]
            with open(f"/proc/{name}/status", "r") as f:
                status = f.read().splitlines()
            ppid = int(next(x.split()[1] for x in status if x.startswith("PPid:")))
            records.append((int(name), ppid, argv))
        except (FileNotFoundError, ProcessLookupError, PermissionError, StopIteration):
            pass
    return records


def matching_processes(script, required_args=()):
    result = []
    for pid, ppid, argv in proc_records():
        if script in argv and all(arg in argv for arg in required_args):
            result.append((pid, ppid, argv))
    return result


def stop_script_processes():
    scripts = {f"{HOME}/supervisor.sh", f"{HOME}/daemon.sh"}
    for sig in (signal.SIGTERM, signal.SIGKILL):
        matches = [(pid, argv) for pid, _, argv in proc_records() if any(s in argv for s in scripts)]
        for pid, _ in matches:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        if matches:
            time.sleep(0.15)


def wait_until(predicate, timeout=4.0, interval=0.02):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return None


def read_lines(path):
    try:
        with open(path, "r") as f:
            return f.readlines()
    except FileNotFoundError:
        return []


def test_success_file():
    success_path = "/home/user/success.txt"
    assert os.path.isfile(success_path), f"File {success_path} does not exist."

    with open(success_path, "r") as f:
        content = f.read()

    assert content == "/mnt/nfs_backup\n", f"Expected /mnt/nfs_backup in {success_path}, but got: {repr(content)}"


def test_logs_content():
    for stage in ["canary", "prod"]:
        log_path = f"/home/user/logs/{stage}.log"
        assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

        with open(log_path, "r") as f:
            lines = f.readlines()

        assert len(lines) >= 10, f"Log file {log_path} has fewer than 10 lines."
        for line in lines[:10]:
            assert line.strip() == "HEARTBEAT /mnt/nfs_backup", f"Unexpected log line in {log_path}: {line.strip()}"


def test_scripts_executable():
    for script in ["daemon.sh", "supervisor.sh"]:
        script_path = f"/home/user/{script}"
        assert os.path.isfile(script_path), f"Script {script_path} does not exist."

        st = os.stat(script_path)
        assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_background_processes_running():
    try:
        output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run 'ps aux' to check running processes.")

    canary_found = False
    prod_found = False

    for line in output.splitlines():
        if "supervisor.sh" in line and "canary" in line and "grep" not in line:
            canary_found = True
        if "supervisor.sh" in line and "prod" in line and "grep" not in line:
            prod_found = True

    assert canary_found, "Could not find a running background process for 'supervisor.sh canary'."
    assert prod_found, "Could not find a running background process for 'supervisor.sh prod'."


def test_live_behavior_and_rollout():
    rollout = f"{HOME}/rollout_monitors.sh"
    daemon = f"{HOME}/daemon.sh"
    supervisor = f"{HOME}/supervisor.sh"
    fstab = f"{HOME}/mock_fstab"

    assert os.path.isfile(rollout), f"File {rollout} does not exist."
    assert os.stat(rollout).st_mode & stat.S_IXUSR, f"Script {rollout} is not executable."

    token = secrets.token_hex(8)
    dynamic_mount = f"/mnt/verifier_{token}"
    direct_mount = f"/mnt/daemon_{token}"
    restart_mount = f"/mnt/restart_{token}"
    restart_stage = f"restart_{token}"
    original_fstab = open(fstab, "rb").read()

    # Exercise daemon output and heartbeat timing directly.
    daemon_proc = subprocess.Popen(
        [daemon, direct_mount], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1
    )
    stamps = []
    direct_lines = []
    try:
        deadline = time.monotonic() + 3
        while len(direct_lines) < 5 and time.monotonic() < deadline:
            ready, _, _ = select.select([daemon_proc.stdout], [], [], 0.4)
            if ready:
                line = daemon_proc.stdout.readline()
                if line:
                    direct_lines.append(line.rstrip("\n"))
                    stamps.append(time.monotonic())
        assert direct_lines == [f"HEARTBEAT {direct_mount}"] * 5
        intervals = [b - a for a, b in zip(stamps, stamps[1:])]
        assert all(0.055 <= x <= 0.8 for x in intervals), f"Heartbeat intervals were not approximately 0.1s: {intervals}"
    finally:
        daemon_proc.terminate()
        try:
            daemon_proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            daemon_proc.kill()
            daemon_proc.wait()

    # Exercise a real supervisor and verify that killing its daemon causes a restart.
    restart_log = f"{LOG_DIR}/{restart_stage}.log"
    try:
        os.remove(restart_log)
    except FileNotFoundError:
        pass
    sup_proc = subprocess.Popen([supervisor, restart_stage, restart_mount], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        assert wait_until(lambda: len(read_lines(restart_log)) >= 3), "Supervisor did not produce daemon heartbeats."
        children = wait_until(lambda: [r for r in matching_processes(daemon, (restart_mount,)) if r[1] == sup_proc.pid])
        assert children, "Supervisor did not run daemon.sh as its foreground child."
        old_pid = children[0][0]
        os.kill(old_pid, signal.SIGKILL)

        replacement = wait_until(lambda: [r for r in matching_processes(daemon, (restart_mount,)) if r[1] == sup_proc.pid and r[0] != old_pid])
        assert replacement, "Supervisor did not restart daemon.sh after it crashed."
        assert wait_until(lambda: any(x.strip() == f"HEARTBEAT {restart_mount}" for x in read_lines(restart_log))), "Restarted daemon produced no heartbeat."
    finally:
        try:
            sup_proc.terminate()
            sup_proc.wait(timeout=1)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                sup_proc.kill()
            except ProcessLookupError:
                pass
        for pid, _, _ in matching_processes(daemon, (restart_mount,)):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    # Execute the submitted master script against an unpredictable fstab entry.
    stop_script_processes()
    with open(fstab, "w") as f:
        f.write("# verifier-generated fstab\n")
        f.write("LABEL=root / ext4 defaults 0 1\n")
        f.write(f"server-{token}:/export {dynamic_mount} nfs4 ro,hard 0 0\n")
        f.write("tmpfs /run tmpfs rw 0 0\n")
    for path in [f"{LOG_DIR}/canary.log", f"{LOG_DIR}/prod.log", f"{HOME}/success.txt"]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    master = None
    try:
        master = subprocess.Popen([rollout], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        prod_seen = False
        deadline = time.monotonic() + 8
        while master.poll() is None and time.monotonic() < deadline:
            prod = matching_processes(supervisor, ("prod", dynamic_mount))
            if prod and not prod_seen:
                prod_seen = True
                assert len(read_lines(f"{LOG_DIR}/canary.log")) >= 10, "Prod started before Canary generated 10 heartbeats."
            time.sleep(0.01)
        if master.poll() is None:
            master.kill()
            master.wait()
            pytest.fail("rollout_monitors.sh did not finish within 8 seconds.")
        stderr = master.stderr.read()
        assert master.returncode == 0, f"rollout_monitors.sh failed: {stderr}"

        assert prod_seen or matching_processes(supervisor, ("prod", dynamic_mount)), "Master script did not start the Prod supervisor."
        assert matching_processes(supervisor, ("canary", dynamic_mount)), "Master script did not leave the Canary supervisor running."
        assert matching_processes(supervisor, ("prod", dynamic_mount)), "Master script did not leave the Prod supervisor running."

        with open(f"{HOME}/success.txt", "r") as f:
            assert f.read() == dynamic_mount + "\n", "Master script did not parse the verifier-generated nfs4 mount point."
        for stage in ("canary", "prod"):
            lines = read_lines(f"{LOG_DIR}/{stage}.log")
            assert len(lines) >= 10, f"{stage} did not generate 10 heartbeats."
            assert all(x.strip() == f"HEARTBEAT {dynamic_mount}" for x in lines[:10]), f"{stage} logged incorrect heartbeat data."
    finally:
        with open(fstab, "wb") as f:
            f.write(original_fstab)

    # Restore the instructed final deployment and leave its background processes running.
    stop_script_processes()
    for path in [f"{LOG_DIR}/canary.log", f"{LOG_DIR}/prod.log", f"{HOME}/success.txt"]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    restored = subprocess.run([rollout], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=8)
    assert restored.returncode == 0, f"Final rollout failed: {restored.stderr}"
    with open(f"{HOME}/success.txt", "r") as f:
        assert f.read() == "/mnt/nfs_backup\n"
    assert matching_processes(supervisor, ("canary", "/mnt/nfs_backup"))
    assert matching_processes(supervisor, ("prod", "/mnt/nfs_backup"))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
