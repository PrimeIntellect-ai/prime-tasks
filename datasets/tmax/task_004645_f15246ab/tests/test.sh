#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import signal
import socket
import subprocess
import threading
import time
import urllib.request
from collections import Counter

import pytest
import redis

EVIL_CORPUS = "/app/data/evil_logs.txt"
CLEAN_CORPUS = "/app/data/clean_logs.txt"
SANITIZER_SOURCE = "/home/user/sanitizer.c"
SANITIZER_BIN = "/home/user/sanitizer"
SOURCE_BIN = "/tmp/sanitizer_from_source"
PIPELINE = "/home/user/pipeline.sh"
FINAL_STATS = "/home/user/final_stats.json"


def run_program(program: str, input_text: str) -> str:
    try:
        result = subprocess.run(
            [program], input=input_text, text=True, capture_output=True,
            check=True, timeout=5
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Sanitizer execution failed: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Sanitizer execution timed out.")


def run_sanitizer(input_text: str) -> str:
    return run_program(SANITIZER_BIN, input_text)


def expected_record(obj):
    result = dict(obj)
    value = result.get("ssn")
    if isinstance(value, str) and re.fullmatch(r"[0-9]{3}-[0-9]{2}-[0-9]{4}", value):
        result["ssn"] = "XXX-XX-XXXX"
    value = result.get("email")
    if isinstance(value, str) and re.fullmatch(r"[^@\s]+@[^@\s]+", value):
        result["email"] = "***@" + value.split("@", 1)[1]
    result["time_bucket"] = obj["timestamp"][:16]
    return result


def parse_single_output(program, obj):
    output = run_program(program, json.dumps(obj) + "\n")
    lines = output.splitlines()
    assert len(lines) == 1, f"Expected exactly one output line, got {len(lines)}"
    try:
        return json.loads(lines[0])
    except json.JSONDecodeError as e:
        pytest.fail(f"Output is not valid JSON: {e}")


def corpus_expected_records():
    records = []
    for path in (EVIL_CORPUS, CLEAN_CORPUS):
        with open(path) as f:
            for line in f:
                if line.strip():
                    records.append(expected_record(json.loads(line)))
    return records


def redis_records(client):
    values = client.lrange("cleaned_logs", 0, -1)
    assert values, "Redis cleaned_logs is empty"
    records = []
    for i, value in enumerate(values):
        try:
            records.append(json.loads(value))
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            pytest.fail(f"Redis cleaned_logs entry {i} is not valid JSON: {e}")
    return records


def expected_counts(records):
    return dict(Counter(record.get("time_bucket", "unknown") for record in records))


def fetch_stats(timeout=3):
    with urllib.request.urlopen("http://localhost:8080/stats", timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def test_sanitizer_exists():
    assert os.path.isfile(SANITIZER_BIN), f"Sanitizer binary {SANITIZER_BIN} is missing."
    assert os.access(SANITIZER_BIN, os.X_OK), f"Sanitizer binary {SANITIZER_BIN} is not executable."
    with open(SANITIZER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SANITIZER_BIN} is not a compiled executable."


@pytest.fixture(scope="session")
def source_bin():
    assert os.path.isfile(SANITIZER_SOURCE), f"C source {SANITIZER_SOURCE} is missing."
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SANITIZER_SOURCE, "-o", SOURCE_BIN],
        text=True, capture_output=True
    )
    assert result.returncode == 0, f"C source does not compile:\n{result.stderr}"
    return SOURCE_BIN


def test_c_source_exists_and_compiles(source_bin):
    assert os.path.isfile(source_bin)
    assert os.access(source_bin, os.X_OK)


def test_evil_corpus_sanitized():
    assert os.path.isfile(EVIL_CORPUS), f"Evil corpus {EVIL_CORPUS} is missing."
    with open(EVIL_CORPUS, "r") as f:
        evil_lines = f.read().strip().split('\n')

    bypassed_files = []
    for i, line in enumerate(evil_lines):
        if not line.strip():
            continue
        output = run_sanitizer(line + "\n").strip()
        try:
            out_json = json.loads(output)
        except json.JSONDecodeError:
            bypassed_files.append(f"Line {i+1}: Output is not valid JSON")
            continue
        if "ssn" in out_json and out_json["ssn"] != "XXX-XX-XXXX":
            bypassed_files.append(f"Line {i+1}: SSN not masked properly")
        if "email" in out_json and not out_json["email"].startswith("***@"):
            bypassed_files.append(f"Line {i+1}: Email not masked properly")
        if "time_bucket" not in out_json:
            bypassed_files.append(f"Line {i+1}: time_bucket missing")
        elif "timestamp" in out_json:
            expected_bucket = out_json["timestamp"][:16]
            if out_json["time_bucket"] != expected_bucket:
                bypassed_files.append(f"Line {i+1}: time_bucket incorrect")
        if out_json != expected_record(json.loads(line)):
            bypassed_files.append(f"Line {i+1}: fields were dropped, added, or changed incorrectly")

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_lines)} evil bypassed: " + ", ".join(bypassed_files))


def test_clean_corpus_preserved():
    assert os.path.isfile(CLEAN_CORPUS), f"Clean corpus {CLEAN_CORPUS} is missing."
    with open(CLEAN_CORPUS, "r") as f:
        clean_lines = f.read().strip().split('\n')

    modified_files = []
    for i, line in enumerate(clean_lines):
        if not line.strip():
            continue
        orig_json = json.loads(line)
        output = run_sanitizer(line + "\n").strip()
        try:
            out_json = json.loads(output)
        except json.JSONDecodeError:
            modified_files.append(f"Line {i+1}: Output is not valid JSON")
            continue
        for k, v in orig_json.items():
            if k not in out_json or out_json[k] != v:
                modified_files.append(f"Line {i+1}: Field {k} modified or missing")
        if "time_bucket" not in out_json:
            modified_files.append(f"Line {i+1}: time_bucket missing")
        elif "timestamp" in out_json:
            expected_bucket = out_json["timestamp"][:16]
            if out_json["time_bucket"] != expected_bucket:
                modified_files.append(f"Line {i+1}: time_bucket incorrect")
        if out_json != expected_record(orig_json):
            modified_files.append(f"Line {i+1}: unexpected fields were added or removed")

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_lines)} clean modified: " + ", ".join(modified_files))


def generated_records():
    token = secrets.token_hex(5)
    records = []
    for i in range(12):
        minute = (7 + i * 3) % 60
        second = (11 + i * 7) % 60
        ssn = f"{(137 + i * 41) % 1000:03d}-{(23 + i * 9) % 100:02d}-{(1049 + i * 317) % 10000:04d}"
        local = f"person.{token}.{i}"
        domain = f"dept{i % 4}.{['com', 'org', 'net'][i % 3]}"
        items = [
            ("id", 10000 + i),
            ("timestamp", f"2025-0{(i % 8) + 1}-{(i % 27) + 1:02d}T{(i * 5) % 24:02d}:{minute:02d}:{second:02d}Z"),
            ("ssn", ssn),
            ("email", f"{local}@{domain}"),
            ("product_code", f"{(900-i):03d}-12-{(3000+i):04d}"),
            ("message", f"leave user{i}@example.com and token {token} unchanged"),
        ]
        random.SystemRandom().shuffle(items)
        records.append(dict(items))
    records.append({
        "timestamp": "2026-12-31T23:59:58Z",
        "ssn": "12-345-6789",
        "email": "not-an-email",
        "product_code": "123-45-6789",
        "message": "literal alpha@sample.org",
    })
    return records


def test_randomized_adversarial_inputs(source_bin):
    records = generated_records()
    for program in (SANITIZER_BIN, source_bin):
        for obj in records:
            assert parse_single_output(program, obj) == expected_record(obj)

        payload = "".join(json.dumps(obj) + "\n" for obj in records)
        output_lines = run_program(program, payload).splitlines()
        assert len(output_lines) == len(records), "Sanitizer must emit one line per input line"
        assert [json.loads(line) for line in output_lines] == [expected_record(obj) for obj in records]


def test_final_stats_exists_and_valid():
    assert os.path.isfile(FINAL_STATS), f"Final stats file {FINAL_STATS} is missing. End-to-end pipeline may not have run."
    with open(FINAL_STATS, "r") as f:
        try:
            stats = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{FINAL_STATS} does not contain valid JSON.")
    assert isinstance(stats, dict), f"Expected {FINAL_STATS} to contain a JSON object."
    assert len(stats) > 0, f"{FINAL_STATS} is empty. Pipeline did not process any logs."


def test_existing_end_to_end_state():
    client = redis.Redis(host="localhost", port=6379, db=0, socket_timeout=2)
    assert client.ping(), "Redis is not running"
    records = redis_records(client)
    allowed = corpus_expected_records()
    for i, record in enumerate(records):
        assert record in allowed, f"Redis entry {i} is not a correctly sanitized producer record"

    api_stats = fetch_stats()
    assert api_stats == expected_counts(records), "Stats API does not reflect Redis cleaned_logs"
    with open(FINAL_STATS) as f:
        saved_stats = json.load(f)
    assert saved_stats == api_stats, "final_stats.json is not the Stats API result for the processed Redis data"


def wait_for_api():
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            fetch_stats(timeout=1)
            return
        except Exception:
            time.sleep(0.1)
    pytest.fail("Stats API did not start on localhost:8080")


def test_z_pipeline_with_runtime_stream():
    assert os.path.isfile(PIPELINE), f"Pipeline script {PIPELINE} is missing."

    subprocess.run(["pkill", "-f", "/home/user/pipeline.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/app/log_producer.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/app/stats_api.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.4)

    client = redis.Redis(host="localhost", port=6379, db=0, socket_timeout=2)
    try:
        client.ping()
    except Exception:
        subprocess.run(["redis-server", "--daemonize", "yes"], check=True)
    client.flushdb()

    api_process = subprocess.Popen(
        ["python3", "/app/stats_api.py"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    wait_for_api()

    source_records = generated_records()[:6]
    expected = [expected_record(obj) for obj in source_records]
    ready = threading.Event()
    errors = []

    def producer():
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            server.bind(("127.0.0.1", 9001))
            server.listen(1)
            server.settimeout(7)
            ready.set()
            conn, _ = server.accept()
            with conn:
                deadline = time.time() + 6.2
                while time.time() < deadline:
                    for obj in source_records:
                        conn.sendall((json.dumps(obj) + "\n").encode())
                        time.sleep(0.04)
                        if time.time() >= deadline:
                            break
        except Exception as e:
            errors.append(str(e))
            ready.set()
        finally:
            server.close()

    thread = threading.Thread(target=producer, daemon=True)
    thread.start()
    assert ready.wait(3), "Runtime log producer failed to start"
    assert not errors, "Runtime log producer failed: " + "; ".join(errors)

    process = subprocess.Popen(
        ["/bin/bash", PIPELINE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    time.sleep(5.5)
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=1)
    time.sleep(0.3)

    assert not errors, "Runtime producer failed while serving pipeline: " + "; ".join(errors)
    records = redis_records(client)
    for i, record in enumerate(records):
        assert record in expected, f"Pipeline pushed incorrect or unsanitized Redis entry {i}: {record}"
    for record in expected:
        assert record in records, "Pipeline did not process every runtime-generated input record"

    assert fetch_stats() == expected_counts(records), "Stats API does not summarize the pipeline's Redis output"
    assert api_process.poll() is None, "Stats API exited during end-to-end verification"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
