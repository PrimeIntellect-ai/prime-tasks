#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any setup services so the verifier can install instrumented services.
pkill -f 'python3 -m http.server 8080' 2>/dev/null || true
pkill -f '/app/tcp_server.py' 2>/dev/null || true
sleep 0.2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import contextlib
import glob
import hashlib
import os
import random
import re
import socket
import subprocess
import tempfile
import time
import uuid

import pytest

PROCESSOR_PATH = "/home/user/processor"
SCRIPT_PATH = "/home/user/process_all.sh"
CLEAN_CORPUS_DIR = "/app/data/clean"
EVIL_CORPUS_DIR = "/app/data/evil"
SERVER_DATA_DIR = "/app/server_data/data"
ACCUMULATOR_LOG = "/app/accumulator_output.log"


def is_valid_row(row):
    parts = row.strip().split(',')
    if len(parts) != 5:
        return False
    id_str, sensor_id_str, temp_str, ts_str, active_str = parts

    if not re.fullmatch(r'[0-9a-f]{8}', id_str):
        return False

    try:
        sensor_id = int(sensor_id_str)
        if not (1 <= sensor_id <= 999):
            return False
    except ValueError:
        return False

    try:
        temp = float(temp_str)
        if not (-50.0 <= temp <= 150.0):
            return False
    except ValueError:
        return False

    try:
        ts = int(ts_str)
        if not (1600000000 <= ts <= 1700000000):
            return False
    except ValueError:
        return False

    if active_str not in ("true", "false"):
        return False

    return True


def is_valid_file(filepath):
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
            if not lines:
                return False
            return all(is_valid_row(line) for line in lines)
    except Exception:
        return False


def calculate_average_temp(filepath):
    total_temp = 0.0
    count = 0
    with open(filepath, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) == 5 and parts[4] == "true":
                total_temp += float(parts[2])
                count += 1
    if count == 0:
        return 0.0
    return total_temp / count


def wait_for_port(port, proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"service on port {port} exited early")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                return
        except OSError:
            time.sleep(0.05)
    raise RuntimeError(f"service on port {port} did not start")


@contextlib.contextmanager
def instrumented_services(document_root, request_log, tcp_log):
    service_dir = tempfile.mkdtemp(prefix="verifier_services_")
    http_py = os.path.join(service_dir, "http.py")
    tcp_py = os.path.join(service_dir, "tcp.py")

    with open(http_py, "w") as f:
        f.write(r'''import http.server
import os
import sys

root, log = sys.argv[1], sys.argv[2]
os.chdir(root)
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        with open(log, "a") as out:
            out.write(self.path + "\n")
        super().do_GET()
    def log_message(self, fmt, *args):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 8080), Handler)
server.serve_forever()
''')

    with open(tcp_py, "w") as f:
        f.write(r'''import socket
import sys

log = sys.argv[1]
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 9090))
    s.listen()
    while True:
        conn, _ = s.accept()
        with conn:
            data = conn.recv(65536)
            if data:
                with open(log, "ab") as out:
                    out.write(data)
                with open("/app/accumulator_output.log", "ab") as out:
                    out.write(data)
''')

    for path in (request_log, tcp_log, ACCUMULATOR_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    http_proc = subprocess.Popen(["python3", http_py, document_root, request_log])
    tcp_proc = subprocess.Popen(["python3", tcp_py, tcp_log])
    try:
        wait_for_port(8080, http_proc)
        wait_for_port(9090, tcp_proc)
        yield
    finally:
        for proc in (http_proc, tcp_proc):
            proc.terminate()
        for proc in (http_proc, tcp_proc):
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def test_processor_exists():
    assert os.path.isfile(PROCESSOR_PATH), f"Executable {PROCESSOR_PATH} not found."
    assert os.access(PROCESSOR_PATH, os.X_OK), f"File {PROCESSOR_PATH} is not executable."


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} not found."
    assert os.access(SCRIPT_PATH, os.X_OK), f"File {SCRIPT_PATH} is not executable."


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failed = []
    for f in clean_files:
        res = subprocess.run([PROCESSOR_PATH, f], capture_output=True, text=True)
        if res.returncode != 0 or "VALID" not in res.stdout:
            clean_failed.append(os.path.basename(f))

    evil_failed = []
    for f in evil_files:
        res = subprocess.run([PROCESSOR_PATH, f], capture_output=True, text=True)
        if res.returncode != 1 or "INVALID" not in res.stdout:
            evil_failed.append(os.path.basename(f))

    error_msgs = []
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_processor_on_fresh_randomized_paths_and_contents():
    rng = random.SystemRandom()
    good_id = ''.join(rng.choice('0123456789abcdef') for _ in range(8))
    sid = rng.randint(2, 998)
    ts = rng.randint(1600000001, 1699999999)
    valid = f"{good_id},{sid},-50.0,1600000000,true\n{good_id},999,150.0,1700000000,false\n"
    cases = [
        valid,
        "",
        valid + "\n",
        f"{good_id[:-1]},{sid},1.5,{ts},true\n",
        f"{good_id[:-1]}z,{sid},1.5,{ts},true\n",
        f"{good_id},0,1.5,{ts},true\n",
        f"{good_id},1000,1.5,{ts},true\n",
        f"{good_id},{sid},-50.0001,{ts},true\n",
        f"{good_id},{sid},150.0001,{ts},true\n",
        f"{good_id},{sid},12.3x,{ts},true\n",
        f"{good_id},{sid},1.5,1599999999,true\n",
        f"{good_id},{sid},1.5,1700000001,true\n",
        f"{good_id},{sid},1.5,{ts},TRUE\n",
        f"{good_id},{sid},1.5,{ts},true,extra\n",
    ]
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="processor_random_") as td:
        for body in cases:
            path = os.path.join(td, uuid.uuid4().hex + ".dat")
            with open(path, "w") as f:
                f.write(body)
            expected_valid = is_valid_file(path)
            res = subprocess.run([PROCESSOR_PATH, path], capture_output=True, text=True, timeout=5)
            assert res.returncode == (0 if expected_valid else 1), path
            assert res.stdout.strip() == ("VALID" if expected_valid else "INVALID"), path


def test_end_to_end_workflow():
    request_log = "/tmp/static_http_requests.log"
    tcp_log = "/tmp/static_tcp_capture.log"
    with instrumented_services("/app/server_data", request_log, tcp_log):
        subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=30)
        time.sleep(0.2)

    assert os.path.isfile(ACCUMULATOR_LOG), f"Accumulator log {ACCUMULATOR_LOG} not found. Did the script run?"
    with open(ACCUMULATOR_LOG, 'r') as f:
        log_content = f.read().strip().splitlines()

    actual_results = {}
    for line in log_content:
        if ':' in line:
            fname, val = line.split(':', 1)
            actual_results[fname.strip()] = val.strip()

    expected_results = {}
    server_files = glob.glob(os.path.join(SERVER_DATA_DIR, "*.csv"))
    for f in server_files:
        if is_valid_file(f):
            avg = calculate_average_temp(f)
            expected_results[os.path.basename(f)] = f"{avg:.2f}"

    missing = []
    wrong = []
    for fname, expected_val in expected_results.items():
        if fname not in actual_results:
            missing.append(fname)
        elif actual_results[fname] != expected_val:
            wrong.append(f"{fname} (expected {expected_val}, got {actual_results[fname]})")
    extra = [fname for fname in actual_results if fname not in expected_results]

    errors = []
    if missing:
        errors.append(f"Missing valid files in output: {', '.join(missing)}")
    if wrong:
        errors.append(f"Incorrect averages calculated: {', '.join(wrong)}")
    if extra:
        errors.append(f"Invalid files incorrectly processed: {', '.join(extra)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_randomized_instrumented_end_to_end_workflow():
    rng = random.SystemRandom()
    root = tempfile.mkdtemp(prefix="dynamic_http_root_")
    data_dir = os.path.join(root, "data")
    os.makedirs(data_dir)

    entries = []
    for _ in range(4):
        name = f"sample_{uuid.uuid4().hex}.csv"
        ident = ''.join(rng.choice('0123456789abcdef') for _ in range(8))
        sid = rng.randint(1, 999)
        ts = rng.randint(1600000000, 1700000000)
        base_cents = rng.randint(-4000, 12000)
        temps = [(base_cents + x) / 100 for x in (0, 3, 6)]
        body = ''.join(f"{ident},{sid},{temp:.2f},{ts},true\n" for temp in temps)
        body += f"{ident},{sid},149.99,{ts},false\n"
        entries.append((name, body))

    invalid_rows = [
        lambda i, s, t: f"{i[:-1]}Z,{s},12.34,{t},true\n",
        lambda i, s, t: f"{i},1000,12.34,{t},true\n",
        lambda i, s, t: f"{i},{s},150.01,{t},true\n",
        lambda i, s, t: f"{i},{s},12.34,{t},False\n",
    ]
    for mutation in invalid_rows:
        name = f"sample_{uuid.uuid4().hex}.csv"
        ident = ''.join(rng.choice('0123456789abcdef') for _ in range(8))
        sid = rng.randint(1, 999)
        ts = rng.randint(1600000000, 1700000000)
        good = f"{ident},{sid},{rng.randint(-20, 90)}.25,{ts},true\n"
        entries.append((name, good + mutation(ident, sid, ts)))

    rng.shuffle(entries)
    for name, body in entries:
        with open(os.path.join(data_dir, name), "w") as f:
            f.write(body)
    with open(os.path.join(root, "files.list"), "w") as f:
        f.write(''.join(name + "\n" for name, _ in entries))

    expected_lines = []
    expected_hashes = []
    for name, _ in entries:
        path = os.path.join(data_dir, name)
        expected_hashes.append(hashlib.sha256(open(path, "rb").read()).hexdigest())
        if is_valid_file(path):
            expected_lines.append(f"{name}:{calculate_average_temp(path):.2f}")

    request_log = "/tmp/dynamic_http_requests.log"
    tcp_log = "/tmp/dynamic_tcp_capture.log"
    invocation_log = "/tmp/processor_invocations.log"
    backup = PROCESSOR_PATH + ".verifier_real"
    try:
        os.remove(invocation_log)
    except FileNotFoundError:
        pass

    os.replace(PROCESSOR_PATH, backup)
    try:
        with open(PROCESSOR_PATH, "w") as f:
            f.write(f'''#!/bin/sh\nif [ -n "$1" ] && [ -f "$1" ]; then\n  h=$(sha256sum "$1" | awk '{{print $1}}')\n  printf '%s\\t%s\\n' "$h" "$1" >> {invocation_log}\nfi\nexec {backup} "$@"\n''')
        os.chmod(PROCESSOR_PATH, 0o755)

        with instrumented_services(root, request_log, tcp_log):
            res = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=30)
            time.sleep(0.3)
    finally:
        try:
            os.remove(PROCESSOR_PATH)
        except FileNotFoundError:
            pass
        os.replace(backup, PROCESSOR_PATH)

    assert res.returncode == 0, f"workflow exited {res.returncode}: {res.stderr}"

    assert os.path.isfile(request_log), "Workflow did not contact the HTTP server"
    requests = open(request_log).read().splitlines()
    assert "/files.list" in requests, "Workflow did not fetch files.list over HTTP"
    for name, _ in entries:
        assert f"/data/{name}" in requests, f"Workflow did not download {name} over HTTP"

    assert os.path.isfile(invocation_log), "Workflow did not invoke /home/user/processor"
    invoked_hashes = [line.split('\t', 1)[0] for line in open(invocation_log).read().splitlines() if '\t' in line]
    for digest in expected_hashes:
        assert digest in invoked_hashes, "Workflow did not validate every downloaded file with processor"

    captured = []
    if os.path.isfile(tcp_log):
        captured = open(tcp_log, "rb").read().decode("utf-8").splitlines()
    assert collections.Counter(captured) == collections.Counter(expected_lines), \
        f"TCP messages differ: expected {expected_lines}, got {captured}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
