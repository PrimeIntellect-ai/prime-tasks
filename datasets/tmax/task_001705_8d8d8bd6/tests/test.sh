#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import re
import secrets
import subprocess
import tempfile


def parse_logs_bin(filepath):
    records = []
    with open(filepath, 'rb') as f:
        while True:
            header = f.read(11)
            if not header:
                break
            if len(header) < 11:
                break
            ts, enc, msg_len = struct.unpack('<QBH', header)
            msg_bytes = f.read(msg_len)
            if enc == 1:
                # UTF-16LE, ascii range only as per spec
                msg = msg_bytes.decode('utf-16le')
            else:
                msg = msg_bytes.decode('utf-8')
            records.append((ts, msg))
    return records


def compute_expected_csv(records):
    if not records:
        return "Timestamp,Event_Type,Message\n"

    accepted = []
    last_msg = None
    for ts, msg in records:
        if msg != last_msg:
            accepted.append((ts, msg))
            last_msg = msg

    t_start = records[0][0]
    t_end = records[-1][0]
    num_buckets = ((t_end - t_start) // 60) + 1

    buckets = [None] * num_buckets
    for ts, msg in accepted:
        idx = (ts - t_start) // 60
        if 0 <= idx < num_buckets:
            if buckets[idx] is None:
                buckets[idx] = (ts, msg)

    expected_lines = ["Timestamp,Event_Type,Message"]
    for i in range(num_buckets):
        bucket_ts = t_start + i * 60
        if buckets[i] is None:
            expected_lines.append(f"{bucket_ts},GAP,MISSING")
        else:
            msg = buckets[i][1]
            event_type = msg.split(' ')[0] if ' ' in msg else msg
            expected_lines.append(f"{bucket_ts},{event_type},{msg}")

    return "\n".join(expected_lines) + "\n"


def write_logs_bin(filepath, records):
    with open(filepath, 'wb') as f:
        for ts, enc, msg in records:
            msg_bytes = msg.encode('utf-16le' if enc == 1 else 'utf-8')
            f.write(struct.pack('<QBH', ts, enc, len(msg_bytes)))
            f.write(msg_bytes)


def normalized_file(path):
    with open(path, 'r') as f:
        return f.read().replace('\r\n', '\n').strip() + '\n'


def test_c_program_exists():
    assert os.path.exists("/home/user/process_logs.c"), "process_logs.c is missing."
    assert os.path.isfile("/home/user/process_logs.c"), "process_logs.c is not a regular file."


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.exists(script_path), "run_pipeline.sh is missing."
    assert os.access(script_path, os.X_OK), "run_pipeline.sh is not executable."
    assert os.path.isfile(script_path), "run_pipeline.sh is not a regular file."


def test_crontab_content():
    crontab_path = "/home/user/crontab.txt"
    assert os.path.exists(crontab_path), "crontab.txt is missing."

    with open(crontab_path, 'r') as f:
        content = f.read().strip()

    pattern = r'^\*/5\s+\*\s+\*\s+\*\s+\*\s+(?:/bin/(?:bash|sh)\s+)?/home/user/run_pipeline\.sh$'
    assert re.match(pattern, content), f"crontab.txt content '{content}' does not match expected schedule for run_pipeline.sh."


def test_output_csv_correctness():
    bin_path = "/home/user/logs.bin"
    csv_path = "/home/user/output.csv"

    assert os.path.exists(csv_path), "output.csv is missing."

    records = parse_logs_bin(bin_path)
    expected_csv = compute_expected_csv(records)

    with open(csv_path, 'r') as f:
        actual_csv = f.read()

    # Normalize line endings
    actual_csv = actual_csv.replace('\r\n', '\n').strip() + '\n'
    expected_csv = expected_csv.replace('\r\n', '\n').strip() + '\n'

    assert actual_csv == expected_csv, "output.csv does not match the expected processed log data."


def test_pipeline_and_compiled_program_on_derived_inputs():
    bin_path = "/home/user/logs.bin"
    csv_path = "/home/user/output.csv"
    source_path = "/home/user/process_logs.c"
    script_path = "/home/user/run_pipeline.sh"

    with open(bin_path, 'rb') as f:
        original_bin = f.read()
    output_existed = os.path.exists(csv_path)
    original_output = None
    if output_existed:
        with open(csv_path, 'rb') as f:
            original_output = f.read()

    token = secrets.token_hex(8)
    base = 1800000000 + secrets.randbelow(1000000)

    try:
        # The pipeline must regenerate output for an input unavailable to the agent.
        pipeline_records = [
            (base + 7, 1, f"LOGIN_{token} first"),
            (base + 8, 0, f"LOGIN_{token} first"),
            (base + 20, 0, f"IGNORED_{token} later"),
            (base + 125, 1, f"WARNING_{token} high_cpu"),
            (base + 126, 0, f"WARNING_{token} high_cpu"),
            (base + 181, 0, f"FINAL_{token}"),
        ]
        write_logs_bin(bin_path, pipeline_records)
        if os.path.exists(csv_path):
            os.unlink(csv_path)

        result = subprocess.run(
            ["/bin/bash", script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            "run_pipeline.sh failed on a derived input:\n"
            + result.stdout + result.stderr
        )
        assert os.path.isfile(csv_path), "run_pipeline.sh did not generate output.csv."
        assert normalized_file(csv_path) == compute_expected_csv(
            [(ts, msg) for ts, enc, msg in pipeline_records]
        ), "run_pipeline.sh did not correctly process a derived logs.bin input."

        # Independently compile and execute the submitted C artifact on another input.
        direct_records = [
            (base + 3, 0, f"START_{token} alpha"),
            (base + 4, 1, f"START_{token} alpha"),
            (base + 61, 1, f"MIDDLE_{token} beta"),
            (base + 70, 0, f"START_{token} alpha"),
            (base + 190, 0, f"END_{token}"),
        ]
        write_logs_bin(bin_path, direct_records)
        if os.path.exists(csv_path):
            os.unlink(csv_path)

        with tempfile.TemporaryDirectory() as td:
            executable = os.path.join(td, "process_logs_verified")
            compile_result = subprocess.run(
                ["gcc", source_path, "-o", executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert compile_result.returncode == 0, (
                "process_logs.c does not compile with gcc:\n"
                + compile_result.stdout + compile_result.stderr
            )
            run_result = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert run_result.returncode == 0, (
                "The compiled process_logs.c program failed:\n"
                + run_result.stdout + run_result.stderr
            )

        assert os.path.isfile(csv_path), "The compiled C program did not generate output.csv."
        assert normalized_file(csv_path) == compute_expected_csv(
            [(ts, msg) for ts, enc, msg in direct_records]
        ), "The compiled C program did not correctly process a derived logs.bin input."
    finally:
        with open(bin_path, 'wb') as f:
            f.write(original_bin)
        if output_existed:
            with open(csv_path, 'wb') as f:
                f.write(original_output)
        elif os.path.exists(csv_path):
            os.unlink(csv_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
