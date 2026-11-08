#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the fixed ports are available for the verifier's controlled end-to-end test.
pkill -f '^python3 /app/services/source.py' 2>/dev/null || true
pkill -f '^python3 /app/services/sink.py' 2>/dev/null || true
sleep 0.2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import socket
import string
import subprocess
import threading
import time

import pytest

PROCESSOR_SOURCE = "/home/user/processor.cpp"
PROCESSOR_BIN = "/home/user/processor"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
PIPELINE_SCRIPT = "/home/user/run_pipeline.sh"


def test_processor_exists_and_executable():
    assert os.path.isfile(PROCESSOR_SOURCE), f"Processor source {PROCESSOR_SOURCE} does not exist."
    assert os.path.isfile(PROCESSOR_BIN), f"Processor binary {PROCESSOR_BIN} does not exist."
    assert os.access(PROCESSOR_BIN, os.X_OK), f"Processor binary {PROCESSOR_BIN} is not executable."
    with open(PROCESSOR_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Processor is not a compiled executable."


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(PIPELINE_SCRIPT), f"Pipeline script {PIPELINE_SCRIPT} does not exist."
    assert os.access(PIPELINE_SCRIPT, os.X_OK), f"Pipeline script {PIPELINE_SCRIPT} is not executable."


def run_processor(input_data: str) -> str:
    result = subprocess.run(
        [PROCESSOR_BIN],
        input=input_data,
        text=True,
        capture_output=True,
        timeout=5
    )
    assert result.returncode == 0, f"Processor exited with {result.returncode}: {result.stderr}"
    return result.stdout


def format_record(record):
    return (
        f"<Reading><ID>{record['id']}</ID><Type>{record['sensor']}</Type>"
        f"<Val>{record['value']:.2f}</Val><Meta>{record['meta']}</Meta></Reading>"
    )


def test_adversarial_corpus_clean():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.jsonl"))
    assert clean_files, f"No clean corpus files found in {CLEAN_CORPUS_DIR}"

    modified_files = []

    for file_path in clean_files:
        with open(file_path, "r") as f:
            lines = f.read().splitlines()

        for line in lines:
            if not line.strip():
                continue

            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            stdout = run_processor(line + "\n")
            output_lines = [l for l in stdout.split("\n") if l.strip()]

            if len(output_lines) != 1:
                modified_files.append(os.path.basename(file_path))
                break

            out_line = output_lines[0]
            expected_val = f"{record['value']:.2f}"

            if not out_line.startswith("<Reading>") or not out_line.endswith("</Reading>"):
                modified_files.append(os.path.basename(file_path))
                break

            if f"<ID>{record['id']}</ID>" not in out_line or \
               f"<Type>{record['sensor']}</Type>" not in out_line or \
               f"<Val>{expected_val}</Val>" not in out_line or \
               f"<Meta>{record['meta']}</Meta>" not in out_line:
                modified_files.append(os.path.basename(file_path))
                break

    if modified_files:
        pytest.fail(f"{len(modified_files)} of {len(clean_files)} clean modified: {', '.join(modified_files)}")


def test_adversarial_corpus_evil():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.jsonl"))
    assert evil_files, f"No evil corpus files found in {EVIL_CORPUS_DIR}"

    bypassed_files = []

    for file_path in evil_files:
        with open(file_path, "r") as f:
            lines = f.read().splitlines()

        for line in lines:
            if not line.strip():
                continue

            stdout = run_processor(line + "\n")
            output_lines = [l for l in stdout.split("\n") if l.strip()]

            if len(output_lines) > 0:
                if os.path.basename(file_path) not in bypassed_files:
                    bypassed_files.append(os.path.basename(file_path))
                break

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}")


def test_generated_mixed_stream_and_validation_rules():
    token = secrets.token_hex(8)
    alphabet = string.ascii_letters + string.digits
    valid = []
    for i in range(16):
        suffix = ''.join(secrets.choice(alphabet) for _ in range(10))
        value = secrets.choice(range(-200, 601)) / 4.0
        valid.append({
            "id": f"ID_{token}_{i}_{suffix}",
            "sensor": f"sensor_{suffix}",
            "value": value,
            "meta": f"station_{token}_{suffix}"
        })

    # Explicitly exercise inclusive bounds.
    valid.extend([
        {"id": f"LOW_{token}", "sensor": "temperature", "value": -50.0, "meta": f"m_{token}"},
        {"id": f"HIGH_{token}", "sensor": "temperature", "value": 150.0, "meta": f"m2_{token}"},
    ])

    base = {"id": f"BAD_{token}", "sensor": "temp", "value": 20.0, "meta": f"ok_{token}"}
    invalid = [
        {k: v for k, v in base.items() if k != "id"},
        {k: v for k, v in base.items() if k != "sensor"},
        {k: v for k, v in base.items() if k != "value"},
        {k: v for k, v in base.items() if k != "meta"},
        dict(base, value=-50.01),
        dict(base, value=150.01),
        dict(base, meta="contains space"),
        dict(base, meta="semi;colon"),
        dict(base, meta="under-score!"),
        dict(base, meta="accent_é"),
        dict(base, meta="line\nbreak"),
        dict(base, meta=""),
        dict(base, value="20.0"),
        dict(base, value=None),
        dict(base, id=123),
        dict(base, sensor=False),
    ]

    entries = []
    expected = []
    for i, record in enumerate(valid):
        entries.append(json.dumps(record, separators=(",", ":")))
        expected.append(format_record(record))
        if i < len(invalid):
            entries.append(json.dumps(invalid[i], separators=(",", ":")))
    entries.extend(["{not valid json", "[]", "null", "", "{\"id\":"])

    stdout = run_processor("\n".join(entries) + "\n")
    assert stdout.splitlines() == expected


def _listener(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(1)
    server.settimeout(8)
    return server


def test_pipeline_end_to_end():
    token = secrets.token_hex(10)
    records = [
        {"id": f"PIPE_{token}_1", "sensor": "humidity", "value": 41.25, "meta": f"remote_{token}"},
        {"id": f"DROP_{token}", "sensor": "humidity", "value": 151.0, "meta": f"remote_{token}"},
        {"id": f"PIPE_{token}_2", "sensor": "wind", "value": -50.0, "meta": f"station_{token}_2"},
        {"id": f"DROP2_{token}", "sensor": "wind", "value": 7.0, "meta": "bad metadata"},
    ]
    payload = ("\n".join(json.dumps(r, separators=(",", ":")) for r in records) + "\n").encode()
    expected = ((format_record(records[0]) + "\n") + (format_record(records[2]) + "\n")).encode()

    source_server = _listener(9001)
    sink_server = _listener(9002)
    received = bytearray()
    errors = []

    def source_worker():
        try:
            conn, _ = source_server.accept()
            with conn:
                conn.sendall(payload)
                conn.shutdown(socket.SHUT_WR)
        except Exception as exc:
            errors.append(f"source: {exc}")
        finally:
            source_server.close()

    def sink_worker():
        try:
            conn, _ = sink_server.accept()
            with conn:
                conn.settimeout(4)
                while len(received) < len(expected):
                    try:
                        chunk = conn.recv(4096)
                    except socket.timeout:
                        break
                    if not chunk:
                        break
                    received.extend(chunk)
        except Exception as exc:
            errors.append(f"sink: {exc}")
        finally:
            sink_server.close()

    source_thread = threading.Thread(target=source_worker)
    sink_thread = threading.Thread(target=sink_worker)
    source_thread.start()
    sink_thread.start()
    time.sleep(0.1)

    try:
        result = subprocess.run(
            [PIPELINE_SCRIPT],
            text=True,
            capture_output=True,
            timeout=8,
        )
    finally:
        source_thread.join(timeout=9)
        sink_thread.join(timeout=9)

    assert result.returncode == 0, f"Pipeline exited with {result.returncode}: {result.stderr}"
    assert not source_thread.is_alive() and not sink_thread.is_alive(), "Pipeline did not complete network I/O"
    assert not errors, "; ".join(errors)
    assert bytes(received) == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
