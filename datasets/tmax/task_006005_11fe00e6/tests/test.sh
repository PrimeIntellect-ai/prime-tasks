#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import secrets
import shutil
import subprocess
import tempfile


def parse_timestamp(ts_str):
    if ts_str.isdigit():
        dt = datetime.datetime.fromtimestamp(int(ts_str), tz=datetime.timezone.utc)
    else:
        ts_str = ts_str.replace('Z', '+00:00')
        dt = datetime.datetime.fromisoformat(ts_str)
    return dt.strftime('%Y-%m-%d %H:%M:%S')


def compute_expected_sql(raw_logs_path):
    with open(raw_logs_path, 'r') as f:
        lines = f.read().strip().split('\n')

    sql_lines = []
    for line in lines:
        if not line.strip():
            continue
        parts = line.strip().split()
        ts_str = parts[0]
        server = parts[1]

        metrics = {}
        for part in parts[2:]:
            k, v = part.split(':')
            metrics[k] = float(v)

        is_anomaly = 1 if metrics.get('cpu', 0) > 90.0 and metrics.get('mem', 0) > 90.0 else 0
        norm_time = parse_timestamp(ts_str)

        for metric_name in ['cpu', 'mem', 'disk']:
            if metric_name in metrics:
                val = metrics[metric_name]
                sql = f"INSERT INTO metrics (log_time, server, metric_name, metric_value, anomaly_flag) VALUES ('{norm_time}', '{server}', '{metric_name}', {val:.1f}, {is_anomaly});"
                sql_lines.append(sql)

    return sql_lines


def assert_output_correct(raw_logs_path, output_path):
    expected_lines = compute_expected_sql(raw_logs_path)
    assert os.path.exists(output_path), f"Output file {output_path} is missing. Did you run your ETL processor?"

    with open(output_path, 'r') as f:
        actual_content = f.read().strip()

    actual_lines = [line.strip() for line in actual_content.split('\n') if line.strip()]
    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} SQL statements, but found {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Mismatch at line {i+1}.\nExpected: {expected}\nActual:   {actual}"


def make_runtime_fixture():
    base_epoch = 1700000000 + secrets.randbelow(20000000)
    iso_epoch = base_epoch + 157
    iso_time = datetime.datetime.fromtimestamp(iso_epoch, tz=datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    token = secrets.token_hex(6).upper()

    cpu1 = 91 + secrets.randbelow(80) / 10.0
    mem1 = 91 + secrets.randbelow(80) / 10.0
    disk1 = secrets.randbelow(1000) / 10.0
    mem2 = 91 + secrets.randbelow(80) / 10.0
    disk2 = secrets.randbelow(1000) / 10.0
    cpu3 = secrets.randbelow(900) / 10.0
    mem3 = secrets.randbelow(900) / 10.0
    disk3 = secrets.randbelow(1000) / 10.0

    return (
        f"{base_epoch} SERVER_{token}A cpu:{cpu1:.1f} mem:{mem1:.1f} disk:{disk1:.1f}\n"
        f"{iso_time} SERVER_{token}B cpu:90.0 mem:{mem2:.1f} disk:{disk2:.1f}\n"
        f"{base_epoch + 311} SERVER_{token}C cpu:{cpu3:.1f} mem:{mem3:.1f} disk:{disk3:.1f}\n"
    )


def run_and_check(executable, raw_logs_path, output_path):
    with open(raw_logs_path, 'w') as f:
        f.write(make_runtime_fixture())

    if os.path.exists(output_path):
        os.unlink(output_path)

    result = subprocess.run(
        [executable],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert_output_correct(raw_logs_path, output_path)


def test_final_state_and_runtime_behavior():
    raw_logs_path = "/home/user/raw_logs.txt"
    output_path = "/home/user/etl_output.sql"
    source_path = "/home/user/etl_processor.c"
    binary_path = "/home/user/etl_processor"

    # Preserve the original verifier assertions against the required final output.
    assert os.path.exists(raw_logs_path), f"Input file {raw_logs_path} is missing."
    assert os.path.exists(output_path), f"Output file {output_path} is missing. Did you run your ETL processor?"
    assert_output_correct(raw_logs_path, output_path)

    assert os.path.exists(source_path), f"C source file {source_path} is missing."
    assert os.path.exists(binary_path), f"Compiled binary {binary_path} is missing."
    assert os.access(binary_path, os.X_OK), f"File {binary_path} is not executable."
    assert os.path.isfile(source_path), f"C source file {source_path} is not a regular file."
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is not a regular file."
    with open(binary_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"File {binary_path} is not a gcc-produced executable."

    with open(raw_logs_path, 'rb') as f:
        original_raw = f.read()
    with open(output_path, 'rb') as f:
        original_output = f.read()

    build_dir = tempfile.mkdtemp(prefix='etl_verify_')
    rebuilt_binary = os.path.join(build_dir, 'etl_processor_rebuilt')
    try:
        compile_result = subprocess.run(
            ['gcc', source_path, '-o', rebuilt_binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"The submitted C source does not compile with gcc.\n"
            f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
        )

        # Exercise both the submitted deliverable and a fresh build of its source
        # on verifier-generated inputs, with expected SQL independently derived.
        run_and_check(binary_path, raw_logs_path, output_path)
        run_and_check(rebuilt_binary, raw_logs_path, output_path)
    finally:
        with open(raw_logs_path, 'wb') as f:
            f.write(original_raw)
        with open(output_path, 'wb') as f:
            f.write(original_output)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
