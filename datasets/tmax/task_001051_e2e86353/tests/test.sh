#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import signal
import subprocess
import time


def get_expected_events():
    raw_logs_dir = "/home/user/raw_logs"
    csv_files = glob.glob(os.path.join(raw_logs_dir, "*.csv"))
    all_filtered_rows = []

    for file_path in csv_files:
        with open(file_path, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]

        parsed_rows = []
        for i, line in enumerate(lines):
            parts = line.split(",", 3)
            if len(parts) != 4:
                continue
            ts, severity, region, message = parts
            if ts == "MISSING":
                prev_ts = int(lines[i - 1].split(",", 1)[0])
                next_ts = int(lines[i + 1].split(",", 1)[0])
                ts = str((prev_ts + next_ts) // 2)
            parsed_rows.append((int(ts), severity, region, message))

        for ts, severity, region, message in parsed_rows:
            if severity == "CRITICAL" or "🛑" in message or "故障" in message:
                all_filtered_rows.append((ts, severity, region, message))

    all_filtered_rows.sort(key=lambda row: row[0])
    return [f"{ts},{sev},{reg},{msg}" for ts, sev, reg, msg in all_filtered_rows]


def run_script(timeout=30):
    output_path = "/home/user/critical_events.csv"
    if os.path.exists(output_path):
        os.unlink(output_path)
    result = subprocess.run(
        ["/home/user/process_logs.sh"],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout,
    )
    assert result.returncode == 0, f"process_logs.sh exited with status {result.returncode}"


def read_output():
    output_path = "/home/user/critical_events.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."
    with open(output_path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def replace_logs(files):
    raw_dir = "/home/user/raw_logs"
    os.makedirs(raw_dir, exist_ok=True)
    for path in glob.glob(os.path.join(raw_dir, "*.csv")):
        os.unlink(path)
    for name, contents in files.items():
        path = os.path.join(raw_dir, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(contents)
        os.chmod(path, 0o666)


def test_original_logs_and_required_artifacts():
    script_path = "/home/user/process_logs.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    expected_lines = get_expected_events()
    run_script()
    actual_lines = read_output()

    assert len(actual_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines, but found {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, \
            f"Mismatch at line {i+1}:\nExpected: {expected}\nActual:   {actual}"


def test_script_recomputes_from_changed_inputs():
    replace_logs({
        "north.csv": (
            "1700000011,INFO,N,booted\n"
            "MISSING,WARNING,N,operator pressed 🛑, immediately\n"
            "1700000016,INFO,N,recovered\n"
            "1700000040,CRITICAL,N,database, primary unavailable\n"
            "1700000090,ERROR,N,ordinary error\n"
        ),
        "south.csv": (
            "1699999999,INFO,S,start\n"
            "1700000020,ERROR,S,冷却装置の故障 detected\n"
            "MISSING,INFO,S,routine event\n"
            "1700000031,CRITICAL,S,power failure\n"
            "1700000100,INFO,S,end\n"
        ),
        "west.csv": (
            "1700000002,CRITICAL,W,first critical\n"
            "1700000010,INFO,W,plain message\n"
            "MISSING,ERROR,W,contains 🛑 and 故障\n"
            "1700000019,INFO,W,plain again\n"
        ),
        "empty_matches.csv": (
            "1700000000,INFO,X,normal\n"
            "1700000001,WARNING,X,still normal\n"
        ),
    })

    expected_lines = get_expected_events()
    run_script()
    actual_lines = read_output()
    assert actual_lines == expected_lines, \
        f"Output was not recomputed correctly.\nExpected: {expected_lines}\nActual: {actual_lines}"


def process_group_members(group_id):
    members = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat", "r", encoding="utf-8") as f:
                stat = f.read()
            fields = stat[stat.rfind(")") + 2:].split()
            if int(fields[2]) == group_id:
                members.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError, IndexError):
            pass
    return members


def open_raw_csvs(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.path.realpath(os.path.join(fd_dir, fd))
                if target.startswith("/home/user/raw_logs/") and target.endswith(".csv"):
                    result.add(target)
            except (FileNotFoundError, PermissionError):
                pass
    except (FileNotFoundError, PermissionError):
        pass
    return result


def test_csv_files_are_actually_processed_in_parallel():
    raw_dir = "/home/user/raw_logs"
    os.makedirs(raw_dir, exist_ok=True)
    for path in glob.glob(os.path.join(raw_dir, "*.csv")):
        os.unlink(path)

    filler_count = 120000
    filler = "1800000001,INFO,LOAD,ordinary filler event for concurrency check\n"
    for i in range(8):
        path = os.path.join(raw_dir, f"bulk_{i}.csv")
        with open(path, "w", encoding="utf-8") as f:
            f.write(f"1800000000,INFO,P{i},start\n")
            f.write(filler * filler_count)
            f.write(f"1800000100,CRITICAL,P{i},critical event {i}\n")
        os.chmod(path, 0o666)

    output_path = "/home/user/critical_events.csv"
    if os.path.exists(output_path):
        os.unlink(output_path)

    proc = subprocess.Popen(
        ["/home/user/process_logs.sh"],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    observed_parallel = False
    deadline = time.monotonic() + 90
    try:
        while proc.poll() is None and time.monotonic() < deadline:
            accesses = []
            for pid in process_group_members(proc.pid):
                for path in open_raw_csvs(pid):
                    accesses.append((pid, path))

            for pid1, path1 in accesses:
                for pid2, path2 in accesses:
                    if pid1 != pid2 and path1 != path2:
                        observed_parallel = True
                        break
                if observed_parallel:
                    break

            if not observed_parallel:
                # Also permit a genuinely multithreaded worker with multiple files open.
                for pid in process_group_members(proc.pid):
                    paths = open_raw_csvs(pid)
                    try:
                        thread_count = len(os.listdir(f"/proc/{pid}/task"))
                    except (FileNotFoundError, PermissionError):
                        thread_count = 0
                    if len(paths) >= 2 and thread_count >= 2:
                        observed_parallel = True
                        break
            time.sleep(0.001)

        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            raise AssertionError("process_logs.sh timed out during the parallel-processing test")
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()

    assert proc.returncode == 0, f"process_logs.sh exited with status {proc.returncode}"
    assert observed_parallel, \
        "No simultaneous processing of distinct CSV input files was observed"
    assert os.path.isfile(output_path), "Script did not produce critical_events.csv"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
