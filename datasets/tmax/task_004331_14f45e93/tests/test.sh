#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import time
import uuid

MONITOR = "/home/user/monitor"
LOG = "/home/user/logs/process_status.log"
BACKUP = LOG + ".1"


def remove_logs():
    for path in (LOG, BACKUP):
        if os.path.exists(path):
            os.remove(path)


def proc_name(pid):
    try:
        with open(f"/proc/{pid}/comm", "r") as f:
            return f.read().strip()
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return None


def matching_pids(name):
    result = []
    for entry in os.listdir("/proc"):
        if entry.isdigit() and proc_name(int(entry)) == name:
            result.append(int(entry))
    return sorted(result)


def read_lines(path=LOG):
    with open(path, "r") as f:
        return [line.rstrip("\n") for line in f]


def test_monitor_executable_exists():
    assert os.path.isfile("/home/user/monitor.cpp"), "/home/user/monitor.cpp does not exist."
    assert os.path.isfile(MONITOR), "/home/user/monitor does not exist."
    assert os.access(MONITOR, os.X_OK), "/home/user/monitor is not executable."
    with open(MONITOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/monitor is not a compiled executable."


def test_monitor_functionality_running_process():
    remove_logs()
    proc = subprocess.Popen(["sleep", "10"])
    time.sleep(0.2)
    try:
        subprocess.run([MONITOR, "sleep"], check=True, timeout=10)
        assert os.path.exists(LOG), "Log file was not created."
        lines = read_lines()
        assert len(lines) >= 1, "Log file is empty."
        last_line = lines[-1]
        match = re.match(r"^STATUS: sleep IS RUNNING \(PID: (\d+)\)$", last_line)
        assert match, f"Log line format incorrect: {last_line}"
        reported_pid = int(match.group(1))
        assert proc_name(reported_pid) == "sleep", "Reported PID does not belong to a sleep process."
        st = os.stat(LOG)
        perms = stat.S_IMODE(st.st_mode)
        assert perms == 0o600, f"Permissions of {LOG} should be 600, but are {oct(perms)}."
    finally:
        proc.terminate()
        proc.wait()


def test_general_lookup_and_lowest_pid():
    remove_logs()
    helper_src = "/tmp/named_process.c"
    helper_bin = "/tmp/named_process"
    with open(helper_src, "w") as f:
        f.write(r'''#include <sys/prctl.h>
#include <unistd.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc != 2 || strlen(argv[1]) > 15) return 2;
    if (prctl(PR_SET_NAME, argv[1], 0, 0, 0) != 0) return 3;
    for (;;) pause();
}
''')
    subprocess.run(["gcc", helper_src, "-o", helper_bin], check=True)
    name = "p" + uuid.uuid4().hex[:11]
    first = subprocess.Popen([helper_bin, name])
    second = None
    try:
        deadline = time.time() + 3
        while time.time() < deadline and proc_name(first.pid) != name:
            time.sleep(0.02)
        assert proc_name(first.pid) == name
        second = subprocess.Popen([helper_bin, name])
        deadline = time.time() + 3
        while time.time() < deadline and proc_name(second.pid) != name:
            time.sleep(0.02)
        assert proc_name(second.pid) == name

        expected = min(matching_pids(name))
        assert expected == min(first.pid, second.pid)
        subprocess.run([MONITOR, name], check=True, timeout=10)
        assert read_lines() == [f"STATUS: {name} IS RUNNING (PID: {expected})"]
        assert proc_name(expected) == name
        assert stat.S_IMODE(os.stat(LOG).st_mode) == 0o600
    finally:
        for process in (second, first):
            if process is not None and process.poll() is None:
                process.terminate()
                process.wait()


def test_monitor_functionality_not_running_process():
    remove_logs()
    name = "n" + uuid.uuid4().hex[:11]
    assert not matching_pids(name)
    subprocess.run([MONITOR, name], check=True, timeout=10)
    assert os.path.exists(LOG), "Log file was not created."
    lines = read_lines()
    assert len(lines) >= 1, "Log file is empty."
    expected = f"STATUS: {name} IS NOT RUNNING"
    assert lines[-1] == expected, f"Expected '{expected}', got '{lines[-1]}'"
    assert stat.S_IMODE(os.stat(LOG).st_mode) == 0o600


def test_monitor_requires_exactly_one_argument():
    remove_logs()
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "w") as f:
        f.write("sentinel\n")
    before = open(LOG, "rb").read()

    no_arg = subprocess.run([MONITOR], timeout=10)
    assert no_arg.returncode != 0, "Monitor must reject zero arguments."
    assert open(LOG, "rb").read() == before, "Zero-argument invocation modified the log."

    two_args = subprocess.run([MONITOR, "one", "two"], timeout=10)
    assert two_args.returncode != 0, "Monitor must reject more than one argument."
    assert open(LOG, "rb").read() == before, "Two-argument invocation modified the log."


def test_monitor_log_rotation():
    remove_logs()
    name = "r" + uuid.uuid4().hex[:11]
    expected_line = f"STATUS: {name} IS NOT RUNNING"

    with open(BACKUP, "w") as f:
        f.write("old backup must be overwritten\n")

    for _ in range(5):
        subprocess.run([MONITOR, name], check=True, timeout=10)

    assert os.path.exists(LOG)
    assert read_lines(LOG) == [expected_line] * 5
    assert read_lines(BACKUP) == ["old backup must be overwritten"], "Backup changed prematurely."

    subprocess.run([MONITOR, name], check=True, timeout=10)
    assert os.path.exists(BACKUP), "Log rotation did not occur; backup file missing."
    assert not os.path.exists(LOG), "Active log should have been renamed after the sixth line."
    assert read_lines(BACKUP) == [expected_line] * 6, "Rotated log contents are incorrect."


def test_cron_configuration():
    cron_file = "/home/user/monitor_cron"
    assert os.path.isfile(cron_file), f"{cron_file} does not exist."
    with open(cron_file, "r") as f:
        content = f.read().strip()
    pattern = r"^\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/monitor\s+qemu-system-x86_64$"
    assert re.search(pattern, content, re.MULTILINE), "Cron configuration is incorrect."


def test_fstab_configuration():
    fstab_file = "/home/user/sandbox_fstab"
    assert os.path.isfile(fstab_file), f"{fstab_file} does not exist."
    with open(fstab_file, "r") as f:
        content = f.read().strip()
    pattern = r"^/home/user/data\s+/sandbox/data\s+none\s+bind,ro,nosuid,nodev\s+0\s+0$"
    assert re.search(pattern, content, re.MULTILINE), "fstab configuration is incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
