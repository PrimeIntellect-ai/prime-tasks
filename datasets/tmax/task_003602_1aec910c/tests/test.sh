#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import subprocess
import time
import uuid
from pathlib import Path

import pytest

SCRIPT = Path("/home/user/run_pipeline.sh")
RAW = Path("/home/user/logs/raw")
CLEAN = Path("/home/user/logs/clean")
SUMMARY = Path("/home/user/logs/summary.csv")


def test_script_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_pipeline_execution():
    script_path = "/home/user/run_pipeline.sh"
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script execution failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )


def test_clean_logs_content():
    clean_dir = "/home/user/logs/clean"
    assert os.path.isdir(clean_dir), f"Directory {clean_dir} does not exist."

    server_01 = os.path.join(clean_dir, "server_01.log")
    assert os.path.isfile(server_01), f"File {server_01} does not exist."
    with open(server_01, "r") as f:
        content_01 = f.read().strip()

    expected_01 = (
        '[2023-10-12T10:00:00Z] 192.168.1.XXX GET /api/user?email=***@example.com 200 {"cc": "****-****-****-3456"}\n'
        '[2023-10-12T10:01:00Z] 10.0.0.XXX POST /checkout 201 {"email": "***@test.org", "cc": "****-****-****-4444"}\n'
        '[2023-10-12T10:02:00Z] 172.16.254.XXX GET /index.html 404 {}'
    ).strip()
    assert content_01 == expected_01, f"Content of {server_01} is incorrect. Masking rules may not have been applied properly."

    server_02 = os.path.join(clean_dir, "server_02.log")
    assert os.path.isfile(server_02), f"File {server_02} does not exist."
    with open(server_02, "r") as f:
        content_02 = f.read().strip()

    expected_02 = (
        '[2023-10-12T10:05:00Z] 8.8.8.XXX GET /api/data 500 {"error": "bad payload"}\n'
        '[2023-10-12T10:06:00Z] 192.168.1.XXX PUT /update?user=***@domain.net 200 {"cc": "****-****-****-6666"}\n'
        '[2023-10-12T10:07:00Z] 10.1.2.XXX GET /health 200 {}'
    ).strip()
    assert content_02 == expected_02, f"Content of {server_02} is incorrect. Masking rules may not have been applied properly."


def test_summary_csv():
    summary_path = "/home/user/logs/summary.csv"
    assert os.path.isfile(summary_path), f"File {summary_path} does not exist."
    with open(summary_path, "r") as f:
        content = f.read().strip()

    expected_csv = (
        "status_code,count\n"
        "200,3\n"
        "201,1\n"
        "404,1\n"
        "500,1"
    ).strip()

    assert content == expected_csv, (
        f"Content of {summary_path} is incorrect. "
        "Ensure the header is correct and the sorting is descending by count, then ascending by status_code."
    )


def mask_line(line):
    line = re.sub(r"(?<![0-9])([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.)[0-9]{1,3}(?![0-9])", r"\1XXX", line)
    line = re.sub(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})", r"***@\1", line)
    line = re.sub(r"(?<![0-9])[0-9]{4}-[0-9]{4}-[0-9]{4}-([0-9]{4})(?![0-9])", r"****-****-****-\1", line)
    return line


def reset_logs():
    RAW.mkdir(parents=True, exist_ok=True)
    CLEAN.mkdir(parents=True, exist_ok=True)
    for directory in (RAW, CLEAN):
        for item in directory.iterdir():
            if item.is_file() or item.is_symlink():
                item.unlink()
    if SUMMARY.exists():
        SUMMARY.unlink()


def test_pipeline_processes_unseen_inputs_and_derives_summary():
    reset_logs()
    token = uuid.uuid4().hex
    fixtures = {
        f"alpha_{token[:8]}.log": [
            f"[2026-01-01T01:02:03Z] 203.0.113.77 GET /lookup?owner={token}.user@example.net 418 {{\"card\": \"4321-8765-1111-9876\"}}",
            "[2026-01-01T01:02:04Z] 198.51.100.9 POST /submit 207 {\"email\": \"first.last+tag@sub.example.org\"}",
        ],
        f"beta_{token[8:16]}.log": [
            "[2026-01-01T01:02:05Z] 10.22.33.44 GET /one 418 {}",
            "[2026-01-01T01:02:06Z] 172.20.30.40 PUT /two 503 {\"cc\": \"0001-0022-0333-4444\"}",
            "[2026-01-01T01:02:07Z] 100.64.2.199 GET /three 207 {}",
        ],
        f"gamma_{token[16:24]}.log": [
            "[2026-01-01T01:02:08Z] 192.0.2.250 DELETE /four 418 {\"email\": \"z9_test@domain.io\"}",
        ],
    }

    for name, lines in fixtures.items():
        (RAW / name).write_text("\n".join(lines) + "\n")

    result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"Dynamic execution failed:\n{result.stderr}"

    for name, lines in fixtures.items():
        output = CLEAN / name
        assert output.is_file(), f"Missing clean output for unseen input {name}"
        expected = "\n".join(mask_line(line) for line in lines) + "\n"
        assert output.read_text() == expected, f"Incorrect dynamically derived masking for {name}"

    assert SUMMARY.read_text().strip() == (
        "status_code,count\n"
        "418,3\n"
        "207,2\n"
        "503,1"
    )


def descendants(root_pid):
    ppid_map = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/status") as f:
                parent = None
                for line in f:
                    if line.startswith("PPid:"):
                        parent = int(line.split()[1])
                        break
            if parent is not None:
                ppid_map.setdefault(parent, []).append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    found = {root_pid}
    pending = [root_pid]
    while pending:
        pid = pending.pop()
        for child in ppid_map.get(pid, []):
            if child not in found:
                found.add(child)
                pending.append(child)
    return found


def test_raw_log_sanitization_actually_runs_concurrently():
    reset_logs()
    file_count = 4
    lines_per_file = 150000
    raw_paths = set()

    for index in range(file_count):
        path = RAW / f"parallel_{index}_{uuid.uuid4().hex[:8]}.log"
        raw_paths.add(str(path))
        line = (
            f"[2026-02-02T00:00:0{index}Z] 10.20.{index}.99 GET "
            f"/item?email=worker{index}@example.com 200 "
            f"{{\"cc\": \"1234-5678-9012-{7000 + index}\"}}\n"
        )
        with open(path, "w") as f:
            for _ in range(lines_per_file):
                f.write(line)

    proc = subprocess.Popen(
        [str(SCRIPT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    observed_parallel = False
    deadline = time.monotonic() + 30

    try:
        while proc.poll() is None and time.monotonic() < deadline:
            open_raw = set()
            for pid in descendants(proc.pid):
                fd_dir = f"/proc/{pid}/fd"
                try:
                    for fd in os.listdir(fd_dir):
                        try:
                            target = os.readlink(f"{fd_dir}/{fd}")
                        except (FileNotFoundError, ProcessLookupError, PermissionError):
                            continue
                        if target in raw_paths:
                            open_raw.add(target)
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    continue
            if len(open_raw) >= 2:
                observed_parallel = True
            time.sleep(0.0005)

        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            pytest.fail("Pipeline timed out during concurrency test")
        stdout, stderr = proc.communicate()
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()

    assert proc.returncode == 0, f"Concurrency run failed:\n{stderr}"
    assert observed_parallel, "No two raw .log files were observed being processed concurrently"

    for raw_path in raw_paths:
        output = CLEAN / Path(raw_path).name
        assert output.is_file(), f"Missing concurrent-run output {output.name}"
        with open(output) as f:
            first = f.readline()
            count = 1 + sum(1 for _ in f)
        assert count == lines_per_file
        assert ".XXX " in first
        assert "***@example.com" in first
        assert "****-****-****-" in first

    assert SUMMARY.read_text().strip() == (
        "status_code,count\n"
        f"200,{file_count * lines_per_file}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
