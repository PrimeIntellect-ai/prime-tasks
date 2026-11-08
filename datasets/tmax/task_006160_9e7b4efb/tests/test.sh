#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import stat
import subprocess
import time
import uuid

SCRIPT = "/home/user/aggregate.sh"
CONFIG = "/home/user/config.json"
SUMMARY = "/home/user/summary.csv"
LOCK = "/home/user/summary.lock"


def clear_summary():
    if os.path.exists(SUMMARY):
        os.remove(SUMMARY)


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."


def test_script_uses_flock():
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "flock" in content, f"Script {SCRIPT} does not seem to use 'flock'."
    assert LOCK in content, f"Script {SCRIPT} does not seem to lock '{LOCK}'."


def test_script_execution_and_output():
    clear_summary()
    datasets = [
        "/home/user/datasets/sample1.json",
        "/home/user/datasets/sample2.csv",
        "/home/user/datasets/sample3.xml",
    ]
    for dataset in datasets:
        result = subprocess.run([SCRIPT, dataset], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed when processing {dataset}. Error: {result.stderr}"
        assert result.stdout == "", f"Script unexpectedly wrote to stdout for {dataset}: {result.stdout!r}"

    assert os.path.exists(SUMMARY), f"{SUMMARY} was not created."
    with open(SUMMARY, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = {
        "sample1.json,GenomeDB,5000",
        "sample2.csv,ClimateData,12500",
        "sample3.xml,OceanTemps,8900",
    }
    actual_lines = set(lines)
    missing = expected_lines - actual_lines
    unexpected = actual_lines - expected_lines
    assert actual_lines == expected_lines, f"Summary contents incorrect. Missing: {missing}, Unexpected: {unexpected}"
    assert len(lines) == 3, f"Expected exactly three output lines, got {len(lines)}: {lines}"


def test_uses_runtime_config_and_input_data():
    token = uuid.uuid4().hex
    directory = "/home/user/datasets"
    paths = {
        "json": os.path.join(directory, f"runtime_{token}.json"),
        "csv": os.path.join(directory, f"runtime_{token}.csv"),
        "xml": os.path.join(directory, f"runtime_{token}.xml"),
    }
    names = {
        "json": f"Json-{token}",
        "csv": f"Csv-{token}",
        "xml": f"Xml-{token}",
    }
    counts = {
        "json": str(100000 + int(token[:5], 16) % 800000),
        "csv": str(100000 + int(token[5:10], 16) % 800000),
        "xml": str(100000 + int(token[10:15], 16) % 800000),
    }
    dynamic_config = {
        "json": {"name_filter": ".custom.label", "count_filter": ".custom.rows"},
        "csv": {"name_column": 5, "count_column": 1},
        "xml": {"name_xpath": "/root/info/name", "count_xpath": "/root/info/amount"},
    }

    with open(CONFIG, "r") as f:
        original_config = f.read()
    try:
        with open(CONFIG, "w") as f:
            json.dump(dynamic_config, f)
        with open(paths["json"], "w") as f:
            json.dump({"custom": {"label": names["json"], "rows": int(counts["json"])}}, f)
        with open(paths["csv"], "w") as f:
            f.write(f"{counts['csv']},unused,a,b,{names['csv']},tail\n")
        with open(paths["xml"], "w") as f:
            f.write(f"<root><info><name>{names['xml']}</name><amount>{counts['xml']}</amount></info></root>\n")

        clear_summary()
        expected = []
        for kind in ("json", "csv", "xml"):
            result = subprocess.run([SCRIPT, paths[kind]], capture_output=True, text=True)
            assert result.returncode == 0, f"Script failed for generated {kind} input: {result.stderr}"
            assert result.stdout == "", f"Script unexpectedly wrote to stdout: {result.stdout!r}"
            expected.append(f"{os.path.basename(paths[kind])},{names[kind]},{counts[kind]}")

        assert os.path.exists(SUMMARY), "summary.csv was not created for generated inputs"
        with open(SUMMARY, "r") as f:
            actual = [line.rstrip("\n") for line in f]
        assert actual == expected, f"Generated inputs/config were not parsed correctly. Expected {expected}, got {actual}"
    finally:
        with open(CONFIG, "w") as f:
            f.write(original_config)
        for path in paths.values():
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def descendants_of(root_pid):
    parent = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat", "r") as f:
                data = f.read()
            after_comm = data[data.rfind(")") + 2:].split()
            parent[int(entry)] = int(after_comm[1])
        except (OSError, ValueError, IndexError):
            pass
    descendants = set()
    changed = True
    while changed:
        changed = False
        for pid, ppid in parent.items():
            if pid not in descendants and (ppid == root_pid or ppid in descendants):
                descendants.add(pid)
                changed = True
    return descendants


def is_flock_for_summary(pid):
    try:
        with open(f"/proc/{pid}/comm", "r") as f:
            if f.read().strip() != "flock":
                return False
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
        if LOCK in cmdline:
            return True
        fd_dir = f"/proc/{pid}/fd"
        for fd in os.listdir(fd_dir):
            try:
                if os.path.realpath(os.path.join(fd_dir, fd)) == LOCK:
                    return True
            except OSError:
                pass
    except OSError:
        return False
    return False


def test_actually_acquires_exclusive_summary_lock_before_writing():
    token = uuid.uuid4().hex
    dataset = f"/home/user/datasets/lock_{token}.json"
    expected = f"{os.path.basename(dataset)},Lock-{token},7319"
    with open(dataset, "w") as f:
        json.dump({"metadata": {"title": f"Lock-{token}"}, "data": {"total_rows": 7319}}, f)

    clear_summary()
    lock_fd = os.open(LOCK, os.O_RDWR | os.O_CREAT, 0o666)
    proc = None
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        proc = subprocess.Popen([SCRIPT, dataset], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        saw_blocked_flock = False
        deadline = time.time() + 2.0
        while time.time() < deadline:
            assert proc.poll() is None, "Script did not wait for the already-held summary lock"
            if any(is_flock_for_summary(pid) for pid in descendants_of(proc.pid)):
                saw_blocked_flock = True
                break
            time.sleep(0.03)

        assert saw_blocked_flock, "No flock process was observed acquiring /home/user/summary.lock"
        assert not os.path.exists(SUMMARY) or os.path.getsize(SUMMARY) == 0, "Script wrote before acquiring the exclusive lock"

        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        stdout, stderr = proc.communicate(timeout=5)
        assert proc.returncode == 0, f"Script failed after the lock was released: {stderr}"
        assert stdout == "", f"Script unexpectedly wrote to stdout: {stdout!r}"
        with open(SUMMARY, "r") as f:
            lines = [line.rstrip("\n") for line in f]
        assert lines == [expected], f"Expected one locked append {expected!r}, got {lines!r}"
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except OSError:
            pass
        os.close(lock_fd)
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        try:
            os.remove(dataset)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
