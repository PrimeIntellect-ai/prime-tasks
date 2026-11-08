#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import secrets
import signal
import subprocess
import threading
from collections import Counter

SCRIPT_PATH = "/home/user/process_logs.sh"
REPORT_PATH = "/home/user/final_report.csv"
LOG_DIR = "/home/user/logs"

EXPECTED_CSV = """Timestamp,IP,Path,Count
2023-11-15T08:30:00Z,192.168.12.000,/api/v1/users,5
2023-11-15T08:40:00Z,10.0.0.000,/login,2
2023-11-15T08:40:00Z,172.16.5.000,/healthcheck,1
"""

ORIGINAL_LOGS = {
    "node_1.log": """[2023-11-15T08:34:12Z] 192.168.12.45 GET /Api/v1/Users?id=5 200
[2023-11-15T08:39:59Z] 192.168.12.45 GET /API/V1/users?id=5 200
[2023-11-15T08:41:02Z] 10.0.0.12 POST /login 201
""",
    "node_2.log": """[2023-11-15T08:31:05Z] 192.168.12.22 GET /api/v1/users 200
[2023-11-15T08:45:10Z] 10.0.0.12 POST /Login 401
""",
    "node_3.log": """[2023-11-15T08:37:12Z] 192.168.12.200 GET /Api/v1/Users?limit=10 200
[2023-11-15T08:49:59Z] 172.16.5.5 GET /healthcheck 200
""",
    "node_4.log": """[2023-11-15T08:35:12Z] 192.168.12.99 GET /Api/v1/Users?limit=10 200
""",
}


def clear_logs():
    os.makedirs(LOG_DIR, exist_ok=True)
    for name in os.listdir(LOG_DIR):
        path = os.path.join(LOG_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            import shutil
            shutil.rmtree(path)
        else:
            os.unlink(path)


def install_logs(logs):
    clear_logs()
    for name, content in logs.items():
        with open(os.path.join(LOG_DIR, name), "w") as f:
            f.write(content)


def run_script(timeout=15):
    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)
    proc = subprocess.Popen(
        [SCRIPT_PATH], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, start_new_session=True
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        raise AssertionError(f"Script timed out. stdout={stdout!r} stderr={stderr!r}")
    assert proc.returncode == 0, (
        f"Script exited with status {proc.returncode}. "
        f"stdout={stdout!r} stderr={stderr!r}"
    )


def expected_csv(logs):
    counts = Counter()
    for content in logs.values():
        for line in content.splitlines():
            if not line.strip():
                continue
            timestamp, ip, method, path, status = line.split()
            timestamp = timestamp[1:-1]
            minute = (int(timestamp[14:16]) // 10) * 10
            bucket = timestamp[:14] + f"{minute:02d}:00Z"
            masked_ip = ip.rsplit(".", 1)[0] + ".000"
            normalized_path = path.split("?", 1)[0].lower()
            counts[(bucket, masked_ip, normalized_path)] += 1

    rows = ["Timestamp,IP,Path,Count"]
    for (bucket, ip, path), count in sorted(counts.items()):
        rows.append(f"{bucket},{ip},{path},{count}")
    return "\n".join(rows) + "\n"


def assert_report(expected):
    assert os.path.isfile(REPORT_PATH), f"Final report {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        content = f.read()
    assert content.strip() == expected.strip(), (
        f"Content of {REPORT_PATH} does not match expected output.\n"
        f"Expected:\n{expected}\nActual:\n{content}"
    )


def test_01_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f"Script {SCRIPT_PATH} is not executable."


def test_02_script_uses_parallel_processing():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    has_ampersand = re.search(r'&\s*$', content, re.MULTILINE) is not None
    has_ampersand_inline = re.search(r'&\s+', content) is not None
    has_xargs_p = re.search(r'xargs\s+.*?-[P|p]', content) is not None
    has_parallel = re.search(r'\bparallel\b', content) is not None
    has_wait = re.search(r'\bwait\b', content) is not None

    uses_parallel = (has_ampersand and has_wait) or (has_ampersand_inline and has_wait) or has_xargs_p or has_parallel
    assert uses_parallel, "Script does not appear to use parallel processing (e.g., '&' with 'wait', 'xargs -P', or 'parallel')."


def test_03_original_fixture_is_generated_correctly():
    install_logs(ORIGINAL_LOGS)
    run_script()
    assert_report(EXPECTED_CSV)


def test_04_changed_inputs_are_processed_correctly():
    token = secrets.token_hex(5)
    upper = token.upper()
    a = secrets.randbelow(200) + 20
    b = secrets.randbelow(200) + 20
    hour = secrets.randbelow(12) + 10
    logs = {
        "node_1.log": (
            f"[2025-07-19T{hour:02d}:27:51Z] 10.{a}.{b}.11 GET /Svc/{upper}/Item?id=1 200\n"
            f"[2025-07-19T{hour:02d}:39:02Z] 172.22.{a}.9 POST /Other/{upper}?debug=yes 201\n"
        ),
        "node_2.log": (
            f"[2025-07-19T{hour:02d}:21:03Z] 10.{a}.{b}.240 POST /svc/{token}/item?different=2 500\n"
        ),
        "node_3.log": (
            f"[2025-07-19T{hour:02d}:29:59Z] 10.{a}.{b}.99 GET /SVC/{upper}/ITEM 404\n"
            f"[2025-07-19T{hour:02d}:31:00Z] 192.0.{b}.7 GET /Health/{upper}?x=1 200\n"
        ),
        "node_4.log": (
            f"[2025-07-19T{hour:02d}:20:00Z] 10.{a}.{b}.1 DELETE /svc/{token}/item?q=z 204\n"
            f"[2025-07-19T{hour:02d}:38:59Z] 172.22.{a}.199 GET /other/{token} 200\n"
        ),
    }
    install_logs(logs)
    run_script()
    assert_report(expected_csv(logs))


def test_05_files_are_actually_processed_in_parallel():
    clear_logs()
    token = secrets.token_hex(6)
    lines = {}
    fifo_paths = []
    for i in range(1, 5):
        name = f"node_{i}.log"
        lines[name] = f"[2026-02-03T14:4{i}:1{i}Z] 198.51.100.{i} GET /Probe/{token}?node={i} 200\n"
        path = os.path.join(LOG_DIR, name)
        os.mkfifo(path, 0o666)
        fifo_paths.append(path)

    gate = threading.Event()
    lock = threading.Lock()
    opened = [0]

    def writer(path, data):
        try:
            fd = os.open(path, os.O_WRONLY)
            with lock:
                opened[0] += 1
                if opened[0] == 4:
                    gate.set()
            if gate.wait(8):
                try:
                    os.write(fd, data.encode())
                except BrokenPipeError:
                    pass
            os.close(fd)
        except OSError:
            pass

    threads = []
    for path, data in zip(fifo_paths, lines.values()):
        thread = threading.Thread(target=writer, args=(path, data), daemon=True)
        thread.start()
        threads.append(thread)

    try:
        run_script(timeout=10)
        assert opened[0] == 4, (
            "The script did not open all four log files concurrently; each log "
            "file must be processed in parallel."
        )
        assert_report(expected_csv(lines))
    finally:
        gate.set()
        for path in fifo_paths:
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                os.close(fd)
            except OSError:
                pass
        for thread in threads:
            thread.join(timeout=1)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
