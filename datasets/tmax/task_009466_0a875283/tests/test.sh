#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tarfile
import time

RESTORED_DIR = "/home/user/restored_app"
EXPECTED_CONTENTS = {
    ".env": b"SECRET_KEY=12345\n",
    "restore_data.log": b"DATA OK\nCORRUPT block 1\nDATA OK\nDATA OK\nCORRUPT block 2\nERROR missing\nCORRUPT block 3\n",
    "server.py": b'import time\nprint("Server starting...")\ntime.sleep(2)\n# Simulating a crash\nexit(1)\n',
}


def test_extraction_and_permissions():
    assert os.path.isdir(RESTORED_DIR), f"Directory {RESTORED_DIR} does not exist."

    expected_files = [".env", "restore_data.log", "server.py"]
    for f in expected_files:
        file_path = os.path.join(RESTORED_DIR, f)
        assert os.path.isfile(file_path), f"File {file_path} is missing."
        assert not os.path.islink(file_path), f"File {file_path} must be an extracted regular file."

    # Ensure the supplied archive itself was not replaced, and compare every
    # restored file byte-for-byte with its corresponding archive member.
    archive_path = "/home/user/backup.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} is missing."
    with tarfile.open(archive_path, "r:gz") as archive:
        members = {}
        for member in archive.getmembers():
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            if name in EXPECTED_CONTENTS:
                assert member.isfile(), f"Archive member {name} is not a regular file."
                extracted = archive.extractfile(member)
                assert extracted is not None
                members[name] = extracted.read()

    assert set(members) == set(EXPECTED_CONTENTS), "Archive does not contain exactly the required service files."
    for name, expected in EXPECTED_CONTENTS.items():
        assert members[name] == expected, f"Archive member {name} was modified."
        with open(os.path.join(RESTORED_DIR, name), "rb") as f:
            actual = f.read()
        assert actual == members[name], f"Restored file {name} does not match the archive."

    env_path = os.path.join(RESTORED_DIR, ".env")
    mode = os.stat(env_path).st_mode
    permissions = stat.S_IMODE(mode)
    assert permissions == 0o600, f"Permissions for {env_path} are {oct(permissions)}, expected 0o600."


def test_corrupt_count():
    count_file = "/home/user/corrupt_count.txt"
    assert os.path.isfile(count_file), f"File {count_file} does not exist."

    with open(count_file, "r") as f:
        content = f.read().strip()

    assert content == "3", f"Expected count to be '3', but got '{content}'."


def test_check_logs_script_computes_count():
    script_file = "/home/user/check_logs.py"
    count_file = "/home/user/corrupt_count.txt"
    log_file = os.path.join(RESTORED_DIR, "restore_data.log")
    assert os.path.isfile(script_file), f"Script {script_file} does not exist."
    assert not os.path.islink(script_file), f"Script {script_file} must be a regular file."

    with open(log_file, "rb") as f:
        original_log = f.read()

    probe = (
        "safe line\n"
        "CORRUPT first\n"
        "XCORRUPTY is not the word\n"
        "two CORRUPT CORRUPT tokens on one line\n"
        "lowercase corrupt\n"
        "prefix-CORRUPT suffix\n"
        "final CORRUPT line\n"
    ).encode()
    expected_probe_count = sum(
        1 for line in probe.decode().splitlines() if re.search(r"\bCORRUPT\b", line)
    )
    assert expected_probe_count != 3

    try:
        with open(log_file, "wb") as f:
            f.write(probe)
        if os.path.exists(count_file):
            os.unlink(count_file)
        result = subprocess.run(
            ["python3", script_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert result.returncode == 0, f"check_logs.py failed: {result.stderr.decode(errors='replace')}"
        assert os.path.isfile(count_file), "check_logs.py did not create corrupt_count.txt."
        with open(count_file, "rb") as f:
            output = f.read()
        allowed = {str(expected_probe_count).encode(), (str(expected_probe_count) + "\n").encode()}
        assert output in allowed, f"check_logs.py produced {output!r}, expected only {expected_probe_count}."
    finally:
        with open(log_file, "wb") as f:
            f.write(original_log)

    # Re-run against the restored archive data and leave the requested final state.
    result = subprocess.run(
        ["python3", script_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, f"check_logs.py failed on restored data: {result.stderr.decode(errors='replace')}"
    with open(count_file, "r") as f:
        content = f.read().strip()
    assert content == "3", f"Expected count to be '3', but got '{content}'."


def test_supervise_script():
    script_file = "/home/user/supervise.sh"
    assert os.path.isfile(script_file), f"Script {script_file} does not exist."

    with open(script_file, "r") as f:
        content = f.read()

    assert "while" in content or "until" in content, f"Script {script_file} does not appear to contain a loop."
    assert "server.py" in content, f"Script {script_file} does not reference server.py."


def _process_info():
    processes = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            with open(f"/proc/{pid}/status", "r") as f:
                status = f.read()
            ppid_match = re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)
            state_match = re.search(r"^State:\s+(\S+)", status, re.MULTILINE)
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
            if ppid_match:
                processes[pid] = (int(ppid_match.group(1)), state_match.group(1) if state_match else "?", argv)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return processes


def _descendants(root_pid, processes):
    found = set()
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _state, _argv) in processes.items():
            if pid not in found and (ppid == root_pid or ppid in found):
                found.add(pid)
                changed = True
    return found


def test_supervisor_running_and_restarts_server():
    pid_file = "/home/user/supervisor.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running."

    cmdline_file = f"/proc/{pid}/cmdline"
    if os.path.isfile(cmdline_file):
        with open(cmdline_file, "r") as f:
            cmdline = f.read().replace('\x00', ' ')
        assert "supervise.sh" in cmdline or "bash" in cmdline or "sh" in cmdline, \
            f"Process {pid} does not seem to be running the supervise script. Cmdline: {cmdline}"

    processes = _process_info()
    assert pid in processes, f"Supervisor process {pid} disappeared."
    _ppid, state, argv = processes[pid]
    assert state != "Z", f"Supervisor process {pid} is a zombie."
    assert any(arg == "/home/user/supervise.sh" for arg in argv), \
        f"PID {pid} is not executing /home/user/supervise.sh: {argv}"
    assert argv and os.path.basename(argv[0]) in ("bash", "supervise.sh"), \
        f"Supervisor is not a bash process: {argv}"

    # server.py sleeps for two seconds and exits. Observe at least three distinct
    # descendant launches, with no long delay between launches.
    launch_times = {}
    deadline = time.monotonic() + 7.0
    while time.monotonic() < deadline and len(launch_times) < 3:
        now = time.monotonic()
        processes = _process_info()
        assert pid in processes and processes[pid][1] != "Z", "Supervisor stopped while being tested."
        for child_pid in _descendants(pid, processes):
            _child_ppid, child_state, child_argv = processes[child_pid]
            if child_state == "Z" or not child_argv:
                continue
            is_python3 = os.path.basename(child_argv[0]).startswith("python3")
            runs_server = "/home/user/restored_app/server.py" in child_argv[1:]
            if is_python3 and runs_server:
                launch_times.setdefault(child_pid, now)
        time.sleep(0.05)

    assert len(launch_times) >= 3, \
        f"Did not observe supervise.sh repeatedly launch server.py; observed PIDs: {sorted(launch_times)}"
    starts = sorted(launch_times.values())[:3]
    assert all((later - earlier) < 2.8 for earlier, later in zip(starts, starts[1:])), \
        f"server.py was not restarted immediately; observed launch times: {starts}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
