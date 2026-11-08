#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import signal
import stat
import subprocess
import time

HOME = "/home/user"
ACTIVE = "[SERVICE_MIGRATION_ACTIVE]"
STOPPED = "[SERVICE_MIGRATION_STOPPED]"


def read_log_lines():
    path = f"{HOME}/migration.log"
    if not os.path.exists(path):
        return []
    with open(path, "r") as f:
        return f.read().splitlines()


def process_exists(pid):
    return os.path.exists(f"/proc/{pid}")


def test_complete_migration_setup():
    assert os.path.exists(f"{HOME}/monitor.c"), "/home/user/monitor.c does not exist"
    assert os.path.exists(f"{HOME}/prepare_migration.sh"), "/home/user/prepare_migration.sh does not exist"

    st = os.stat(f"{HOME}/prepare_migration.sh")
    assert bool(st.st_mode & stat.S_IXUSR), "/home/user/prepare_migration.sh is not executable"

    # Become a child subreaper so the background daemon is waitable after the
    # preparation shell exits, allowing its true exit status to be checked.
    libc = ctypes.CDLL(None, use_errno=True)
    assert libc.prctl(36, 1, 0, 0, 0) == 0, "failed to enable child subreaper"

    for name in ("monitor", "monitor.pid", "migration.log", "firewall.sh", "routes.sh", "fstab.append"):
        path = f"{HOME}/{name}"
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    pid = None
    try:
        result = subprocess.run(
            [f"{HOME}/prepare_migration.sh"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"prepare_migration.sh failed with return code {result.returncode}\n{result.stderr}"
        )

        assert os.path.exists(f"{HOME}/firewall.sh"), "/home/user/firewall.sh was not created"
        with open(f"{HOME}/firewall.sh", "r") as f:
            firewall_content = f.read().strip()
        assert firewall_content == "iptables -t nat -A PREROUTING -i eth1 -p tcp --dport 443 -j DNAT --to-destination 10.10.10.50:8443", "firewall.sh content is incorrect"

        assert os.path.exists(f"{HOME}/routes.sh"), "/home/user/routes.sh was not created"
        with open(f"{HOME}/routes.sh", "r") as f:
            routes_content = f.read().strip()
        assert routes_content == "ip route add 10.10.10.0/24 via 172.16.0.1 dev eth1", "routes.sh content is incorrect"

        assert os.path.exists(f"{HOME}/fstab.append"), "/home/user/fstab.append was not created"
        with open(f"{HOME}/fstab.append", "r") as f:
            fstab_content = f.read().strip()
        assert fstab_content == "10.10.10.50:/var/nfs /mnt/shared nfs rw,hard,intr 0 0", "fstab.append content is incorrect"

        assert os.path.exists(f"{HOME}/monitor"), "/home/user/monitor was not created"
        monitor_st = os.stat(f"{HOME}/monitor")
        assert stat.S_ISREG(monitor_st.st_mode), "/home/user/monitor is not a regular executable"
        assert monitor_st.st_mode & 0o111, "/home/user/monitor is not executable"
        with open(f"{HOME}/monitor", "rb") as f:
            assert f.read(4) == b"\x7fELF", "/home/user/monitor is not a compiled ELF executable"

        assert os.path.exists(f"{HOME}/monitor.pid"), "/home/user/monitor.pid was not created"
        with open(f"{HOME}/monitor.pid", "r") as f:
            pid_str = f.read().strip()
        assert pid_str.isdigit(), "/home/user/monitor.pid does not contain a valid integer PID"
        pid = int(pid_str)

        try:
            os.kill(pid, 0)
        except OSError:
            assert False, f"Process with PID {pid} is not running"

        proc_exe = f"/proc/{pid}/exe"
        assert os.path.exists(proc_exe), f"Process with PID {pid} has no executable"
        assert os.path.samefile(proc_exe, f"{HOME}/monitor"), (
            f"PID {pid} is not the compiled /home/user/monitor executable"
        )

        # Observe several successive writes over a runtime selected only during
        # verification. Each newly observed line must arrive at approximately
        # one-second intervals, and the daemon must remain alive throughout.
        duration = secrets.SystemRandom().uniform(5.2, 6.8)
        start = time.monotonic()
        events = []
        previous_count = 0

        while time.monotonic() - start < duration:
            assert process_exists(pid), "monitor stopped before receiving SIGTERM"
            assert os.path.samefile(proc_exe, f"{HOME}/monitor"), "monitor PID changed executable"

            lines = read_log_lines()
            assert all(line == ACTIVE for line in lines), (
                "migration.log contained an unexpected line before SIGTERM"
            )
            assert len(lines) >= previous_count, "migration.log lost active entries"
            assert len(lines) - previous_count <= 1, (
                "monitor appended multiple active entries without one-second spacing"
            )
            if len(lines) > previous_count:
                events.append(time.monotonic())
            previous_count = len(lines)
            time.sleep(0.05)

        assert os.path.exists(f"{HOME}/migration.log"), "/home/user/migration.log was not created"
        assert previous_count >= int(duration) - 1, (
            "monitor did not append active messages continuously every second"
        )
        assert events, "migration.log does not contain [SERVICE_MIGRATION_ACTIVE]"
        for earlier, later in zip(events, events[1:]):
            interval = later - earlier
            assert 0.70 <= interval <= 1.30, (
                f"active messages were not appended every second (interval {interval:.2f}s)"
            )
        assert time.monotonic() - events[-1] <= 1.35, (
            "monitor stopped appending active messages while still running"
        )

        os.kill(pid, signal.SIGTERM)

        status = None
        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            try:
                waited_pid, waited_status = os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                assert False, "monitor was not the background process launched by the preparation script"
            if waited_pid == pid:
                status = waited_status
                break
            time.sleep(0.05)

        assert status is not None, f"Process with PID {pid} did not terminate after receiving SIGTERM"
        assert os.WIFEXITED(status), "monitor was terminated by a signal instead of exiting cleanly"
        assert os.WEXITSTATUS(status) == 0, "monitor did not exit with status code 0"

        lines = read_log_lines()
        assert lines[-1] == STOPPED, "The last line of migration.log is not [SERVICE_MIGRATION_STOPPED]"
        assert lines.count(STOPPED) == 1, "monitor did not append exactly one stopped message"
        assert all(line == ACTIVE for line in lines[:-1]), "migration.log contains unexpected output"

        final_content = lines[:]
        time.sleep(0.4)
        assert read_log_lines() == final_content, "migration.log changed after the monitor exited"
        pid = None
    finally:
        if pid is not None:
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
            try:
                os.waitpid(pid, 0)
            except (ChildProcessError, OSError):
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
