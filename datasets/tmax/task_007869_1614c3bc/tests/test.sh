#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
import time

HOME = "/home/user"
SRC = "/home/user/monitor_src/resource_monitor.c"
DEPLOY = "/home/user/deploy.sh"
BIN_DIR = "/home/user/deploy/bin"
LOGS_DIR = "/home/user/deploy/logs"
MONITOR = "/home/user/deploy/bin/monitor"
ACTIVE = "/home/user/deploy/logs/active.csv"
CURRENT = "/home/user/deploy/current_log"
CSV_RE = re.compile(r"^[0-9]+,[0-9]+\.[0-9]+,[0-9]+,[0-9]+$")


def proc_values():
    with open("/proc/loadavg", "r") as f:
        load = float(f.read().split()[0])

    total = free = None
    with open("/proc/meminfo", "r") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                total = int(line.split()[1])
            elif line.startswith("MemFree:"):
                free = int(line.split()[1])
    assert total is not None and free is not None
    return load, total - free, total


def parse_line(line):
    assert CSV_RE.fullmatch(line), f"Invalid CSV line: {line!r}"
    timestamp, load, used, total = line.split(",")
    return int(timestamp), float(load), int(used), int(total)


def run_as_user(argv, cwd=None, timeout=30):
    pw = __import__("pwd").getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(pw.pw_gid)
        os.setuid(pw.pw_uid)

    env = os.environ.copy()
    env["HOME"] = HOME
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=demote,
    )


def assert_final_layout():
    assert os.path.isdir(BIN_DIR), f"Directory {BIN_DIR} does not exist."
    assert os.path.isdir(LOGS_DIR), f"Directory {LOGS_DIR} does not exist."
    assert stat.S_IMODE(os.stat(BIN_DIR).st_mode) == 0o700, \
        f"Permissions for {BIN_DIR} are not 700."

    assert os.path.isfile(SRC), f"Source file {SRC} does not exist."
    assert os.path.isfile(DEPLOY), f"Deployment script {DEPLOY} does not exist."
    assert os.access(DEPLOY, os.X_OK), f"Deployment script {DEPLOY} is not executable."

    assert os.path.islink(CURRENT), f"{CURRENT} is not a symbolic link."
    target = os.readlink(CURRENT)
    assert target == ACTIVE, f"Symlink target is {target!r}, expected {ACTIVE!r}."

    assert os.path.isfile(MONITOR), f"Executable {MONITOR} does not exist."
    assert os.access(MONITOR, os.X_OK), f"Executable {MONITOR} is not executable."
    with open(MONITOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "monitor is not a compiled ELF executable."

    assert os.path.isfile(ACTIVE), f"Log file {ACTIVE} does not exist."


def validate_runtime_line(line, before_time, after_time, before_proc, after_proc):
    timestamp, load, used, total = parse_line(line)
    assert before_time <= timestamp <= after_time, \
        f"Timestamp {timestamp} was not produced during monitor execution."

    load_low = min(before_proc[0], after_proc[0]) - 0.20
    load_high = max(before_proc[0], after_proc[0]) + 0.20
    assert load_low <= load <= load_high, \
        f"Load {load} does not agree with /proc/loadavg values."

    assert total == before_proc[2] == after_proc[2], \
        f"MemTotal {total} does not agree with /proc/meminfo."
    tolerance_kb = 262144
    used_low = min(before_proc[1], after_proc[1]) - tolerance_kb
    used_high = max(before_proc[1], after_proc[1]) + tolerance_kb
    assert used_low <= used <= used_high, \
        f"MemUsed {used} does not agree with MemTotal-MemFree from /proc/meminfo."
    assert 0 <= used <= total


def main():
    # Preserve all original final-state checks and require exactly the one requested run.
    assert_final_layout()
    with open(ACTIVE, "rb") as f:
        original_log = f.read()
    assert original_log.endswith(b"\n"), "active.csv must end with a newline."
    original_lines = original_log.decode("ascii").splitlines()
    assert len(original_lines) == 1, \
        f"active.csv must contain exactly one execution record, found {len(original_lines)}."
    ts, load, used, total = parse_line(original_lines[0])
    current_total = proc_values()[2]
    assert total == current_total, "Logged MemTotal does not agree with /proc/meminfo."
    assert 0 <= used <= total and load >= 0
    assert 1577836800 <= ts <= int(time.time()), "Logged timestamp is not a valid past Unix time."
    assert abs(os.stat(ACTIVE).st_mtime - ts) <= 5, \
        "Logged timestamp does not match when active.csv was written."

    with open(DEPLOY, "r", errors="replace") as f:
        deploy_text = f.read()
    assert re.search(r"\bgcc\b", deploy_text), "deploy.sh does not invoke gcc."

    # Force deploy.sh to reconstruct the executable and repair an incorrect symlink.
    os.unlink(MONITOR)
    os.unlink(CURRENT)
    os.symlink("/tmp/incorrect-monitor-log", CURRENT)

    first = run_as_user([DEPLOY])
    assert first.returncode == 0, \
        f"deploy.sh failed as user: {first.stderr.decode(errors='replace')}"
    assert_final_layout()
    with open(ACTIVE, "rb") as f:
        assert f.read() == original_log, "deploy.sh changed or duplicated existing log data."

    second = run_as_user([DEPLOY])
    assert second.returncode == 0, \
        f"Second deploy.sh run failed: {second.stderr.decode(errors='replace')}"
    assert_final_layout()
    with open(ACTIVE, "rb") as f:
        assert f.read() == original_log, "Repeated deployment changed or duplicated log data."

    # Exercise argument validation.
    assert run_as_user([MONITOR]).returncode != 0, "monitor accepted no arguments."
    with tempfile.TemporaryDirectory(dir="/tmp") as td:
        extra1 = os.path.join(td, "extra1.csv")
        extra2 = os.path.join(td, "extra2.csv")
        assert run_as_user([MONITOR, extra1, extra2]).returncode != 0, \
            "monitor accepted more than one argument."
        assert not os.path.exists(extra1) and not os.path.exists(extra2)

        assert run_as_user([MONITOR, "relative.csv"], cwd=td).returncode != 0, \
            "monitor accepted a relative output path."
        assert not os.path.exists(os.path.join(td, "relative.csv"))
        assert run_as_user([MONITOR, td]).returncode != 0, \
            "monitor reported success when the output path could not be opened as a file."

        # Run the rebuilt artifact and derive expected values directly from /proc.
        output = os.path.join(td, "monitor.csv")
        before_proc = proc_values()
        before_time = int(time.time())
        result = run_as_user([MONITOR, output])
        after_time = int(time.time())
        after_proc = proc_values()
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        with open(output, "r") as f:
            lines = f.read().splitlines()
        assert len(lines) == 1, "One monitor invocation must append exactly one line."
        validate_runtime_line(lines[0], before_time, after_time, before_proc, after_proc)

        first_line = lines[0]
        before_proc = proc_values()
        before_time = int(time.time())
        result = run_as_user([MONITOR, output])
        after_time = int(time.time())
        after_proc = proc_values()
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        with open(output, "r") as f:
            lines = f.read().splitlines()
        assert len(lines) == 2, "Each invocation must append exactly one line."
        assert lines[0] == first_line, "monitor overwrote existing log data instead of appending."
        validate_runtime_line(lines[1], before_time, after_time, before_proc, after_proc)

    # Verification runs must not alter the requested active.csv execution count.
    with open(ACTIVE, "rb") as f:
        assert f.read() == original_log


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
