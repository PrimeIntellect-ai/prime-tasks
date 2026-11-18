#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import datetime
import json
import os
import queue
import random
import re
import secrets
import stat
import subprocess
import tempfile
import threading
import time

import pytest

BINARY = "/home/user/log_sanitizer/target/release/log_sanitizer"
WRAPPER = "/home/user/run_bridge.sh"


def run_sanitizer(input_path, output_path, timeout=20, env=None):
    try:
        return subprocess.run(
            [BINARY, "--input", input_path, "--output", output_path],
            check=True,
            capture_output=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of sanitizer failed: {e.stderr.decode(errors='replace')}")
    except subprocess.TimeoutExpired:
        pytest.fail("Sanitizer timed out")


def nonempty_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\r\n") for line in f if line.strip()]


def valid_timestamp(value):
    if not isinstance(value, str):
        return False
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z", value):
        return False
    try:
        datetime.datetime.fromisoformat(value[:-1] + "+00:00")
        return True
    except ValueError:
        return False


def valid_value(value):
    if isinstance(value, str):
        lowered = value.lower()
        return "<script>" not in lowered and "drop table" not in lowered
    if isinstance(value, list):
        return all(valid_value(item) for item in value)
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "status_code":
                if isinstance(item, bool) or not isinstance(item, int) or not 100 <= item <= 599:
                    return False
            if key == "timestamp" and not valid_timestamp(item):
                return False
            if not valid_value(item):
                return False
    return True


def expected_survivors(raw_lines):
    result = []
    for raw in raw_lines:
        try:
            value = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if isinstance(value, dict) and valid_value(value):
            result.append(raw)
    return result


def test_binary_exists():
    assert os.path.isfile(BINARY), f"Rust binary not found at {BINARY}. Did you compile it in release mode?"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The required compiled binary is not an ELF executable"
    assert os.path.isfile("/home/user/log_sanitizer/Cargo.toml"), "Rust Cargo project is missing"


def test_wrapper_script_exists():
    assert os.path.isfile(WRAPPER), f"Wrapper script not found at {WRAPPER}."
    st = os.stat(WRAPPER)
    assert bool(st.st_mode & stat.S_IXUSR), f"Wrapper script at {WRAPPER} is not executable."


def test_adversarial_corpus():
    clean_corpus = "/app/corpus/clean/clean_logs.jsonl"
    evil_corpus = "/app/corpus/evil/evil_logs.jsonl"
    with tempfile.NamedTemporaryFile(delete=False) as tmp_clean_out:
        clean_out_path = tmp_clean_out.name
    with tempfile.NamedTemporaryFile(delete=False) as tmp_evil_out:
        evil_out_path = tmp_evil_out.name
    try:
        run_sanitizer(clean_corpus, clean_out_path)
        clean_input_lines = nonempty_lines(clean_corpus)
        clean_output_lines = nonempty_lines(clean_out_path)
        clean_input_set = set(clean_input_lines)
        clean_output_set = set(clean_output_lines)
        missing_clean = clean_input_set - clean_output_set
        assert not missing_clean, f"{len(missing_clean)} of {len(clean_input_set)} clean logs modified or rejected. Example missing: {list(missing_clean)[:1]}"
        assert collections.Counter(clean_output_lines) == collections.Counter(clean_input_lines), "Clean output contained modified, duplicate, or extra lines"

        run_sanitizer(evil_corpus, evil_out_path)
        evil_input_lines = nonempty_lines(evil_corpus)
        evil_output_lines = nonempty_lines(evil_out_path)
        evil_output_set = set(evil_output_lines)
        assert not evil_output_set, f"{len(evil_output_set)} of {len(evil_input_lines)} evil logs bypassed validation. Example bypassed: {list(evil_output_set)[:1]}"
    finally:
        for path in (clean_out_path, evil_out_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_generated_mixed_input_and_exact_output():
    rng = random.SystemRandom()
    token = secrets.token_hex(10)
    valid_timestamps = [
        "2024-02-29T00:00:00Z",
        "2025-12-31T23:59:59.123456Z",
        "2001-01-01T01:02:03.4Z",
    ]
    invalid_timestamps = [
        "2023-10-12 07:20:50",
        "2023-02-29T07:20:50Z",
        "2023-10-12T07:20:50",
        "not-a-time",
    ]
    records = [
        {"id": token + "-boundary-low", "status_code": 100, "timestamp": valid_timestamps[0]},
        {"id": token + "-boundary-high", "status_code": 599, "timestamp": valid_timestamps[1]},
        {"id": token + "-nested-status-low", "nested": {"items": [{"status_code": 99}]}},
        {"id": token + "-nested-status-high", "nested": [{"x": {"status_code": 600}}]},
        {"id": token + "-bool-status", "status_code": True},
        {"id": token + "-float-status", "status_code": 200.0},
        {"id": token + "-nested-script", "nested": [1, {"message": "x<ScRiPt>y"}]},
        {"id": token + "-nested-drop", "nested": {"deeper": ["please DrOp TaBlE accounts"]}},
        {"id": token + "-bad-time", "nested": {"timestamp": invalid_timestamps[1]}},
        {"id": token + "-safe-key", "DROP TABLE is only a key": 7, "status_code": 204},
        {"id": token + "-plain", "array": [None, False, 12, {"message": "safe"}]},
    ]
    for i in range(70):
        kind = rng.randrange(6)
        obj = {"id": f"{token}-{i}-{secrets.token_hex(4)}", "payload": {"n": i, "text": "ordinary value"}}
        if kind == 0:
            obj["status_code"] = rng.randint(100, 599)
            obj["timestamp"] = rng.choice(valid_timestamps)
        elif kind == 1:
            obj["payload"]["status_code"] = rng.choice([rng.randint(-1000, 99), rng.randint(600, 2000)])
        elif kind == 2:
            obj["payload"]["timestamp"] = rng.choice(invalid_timestamps)
        elif kind == 3:
            obj["payload"]["values"] = ["safe", "prefix <SCRIPT> suffix"]
        elif kind == 4:
            obj["payload"]["query"] = "prefix drop table suffix"
        else:
            obj["payload"]["timestamp"] = rng.choice(valid_timestamps)
        records.append(obj)

    raw_lines = [json.dumps(obj, ensure_ascii=False, separators=(",", ":")) for obj in records]
    raw_lines.extend([
        "{malformed-" + token,
        "[1,2,3]",
        json.dumps("a top-level string " + token),
        '{"id":"' + token + '-truncated"',
    ])
    rng.shuffle(raw_lines)
    expected = expected_survivors(raw_lines)

    with tempfile.TemporaryDirectory(prefix="sanitizer-random-") as td:
        input_path = os.path.join(td, secrets.token_hex(8) + ".jsonl")
        output_path = os.path.join(td, secrets.token_hex(8) + ".out")
        with open(input_path, "w", encoding="utf-8", newline="\n") as f:
            for line in raw_lines:
                f.write(line + "\n")
        run_sanitizer(input_path, output_path)
        actual = nonempty_lines(output_path)
        assert collections.Counter(actual) == collections.Counter(expected), "Generated input was not sanitized exactly; output had missing, modified, duplicate, or extra records"


def test_parallel_processing_is_exercised():
    with tempfile.TemporaryDirectory(prefix="sanitizer-parallel-") as td:
        input_path = os.path.join(td, secrets.token_hex(8) + ".jsonl")
        output_path = os.path.join(td, secrets.token_hex(8) + ".out")
        payload = json.dumps({"timestamp": "2024-01-01T00:00:00Z", "status_code": 200, "nested": {"padding": "x" * 100, "bad": "<ScRiPt>"}}, separators=(",", ":")) + "\n"
        with open(input_path, "w", encoding="utf-8") as f:
            for _ in range(350000):
                f.write(payload)

        env = os.environ.copy()
        env["RAYON_NUM_THREADS"] = "4"
        proc = subprocess.Popen([BINARY, "--input", input_path, "--output", output_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        cpu_seen = {}
        max_tasks = 0
        deadline = time.monotonic() + 30
        while proc.poll() is None and time.monotonic() < deadline:
            task_dir = f"/proc/{proc.pid}/task"
            try:
                tids = os.listdir(task_dir)
                max_tasks = max(max_tasks, len(tids))
                for tid in tids:
                    try:
                        fields = open(os.path.join(task_dir, tid, "stat"), "r").read().split()
                        cpu_seen[tid] = max(cpu_seen.get(tid, 0), int(fields[13]) + int(fields[14]))
                    except (FileNotFoundError, ProcessLookupError, ValueError, IndexError):
                        pass
            except FileNotFoundError:
                pass
            time.sleep(0.002)
        if proc.poll() is None:
            proc.kill()
            proc.communicate()
            pytest.fail("Sanitizer timed out during parallel workload")
        stdout, stderr = proc.communicate()
        assert proc.returncode == 0, stderr.decode(errors="replace")
        assert max_tasks >= 2, "Sanitizer did not create any worker thread during a large workload"
        assert sum(1 for ticks in cpu_seen.values() if ticks > 0) >= 2, "A large workload consumed CPU on only one thread instead of being processed in parallel"
        assert nonempty_lines(output_path) == [], "Invalid parallel-workload records were not all rejected"


def test_bridge_filters_fifo_and_streams_before_eof():
    raw_fifo = "/tmp/raw_logs.fifo"
    clean_fifo = "/tmp/clean_logs.fifo"
    for path in (raw_fifo, clean_fifo):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
        os.mkfifo(path)

    received = queue.Queue()
    reader_error = []

    def reader():
        try:
            with open(clean_fifo, "r", encoding="utf-8") as f:
                while True:
                    line = f.readline()
                    if line == "":
                        break
                    received.put(line.rstrip("\r\n"))
        except BaseException as exc:
            reader_error.append(exc)

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    proc = subprocess.Popen([WRAPPER], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    token = secrets.token_hex(12)
    first = json.dumps({"id": token + "-first", "timestamp": "2024-01-02T03:04:05.6Z", "status_code": 200}, separators=(",", ":"))
    bad = json.dumps({"id": token + "-bad", "nested": ["dRoP tAbLe secrets"]}, separators=(",", ":"))
    second = json.dumps({"id": token + "-second", "nested": {"status_code": 599, "message": "safe"}}, separators=(",", ":"))
    try:
        with open(raw_fifo, "w", encoding="utf-8", buffering=1) as writer:
            writer.write(first + "\n")
            writer.flush()
            try:
                first_received = received.get(timeout=5)
            except queue.Empty:
                pytest.fail("Bridge buffered FIFO input until EOF instead of emitting a valid line continuously")
            assert first_received == first, "Bridge modified or rejected the first valid streaming record"
            writer.write(bad + "\n")
            writer.write(second + "\n")
            writer.flush()
        try:
            second_received = received.get(timeout=5)
        except queue.Empty:
            pytest.fail("Bridge did not emit the later valid FIFO record")
        assert second_received == second, "Bridge failed to filter the FIFO stream correctly"
        time.sleep(0.3)
        assert received.empty(), "Bridge emitted an invalid or extra FIFO record"
        assert not reader_error, f"FIFO reader failed: {reader_error}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        for path in (raw_fifo, clean_fifo):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
