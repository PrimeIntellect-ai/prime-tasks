#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_c_source_file_exists():
    source_path = "/home/user/track_config.c"
    assert os.path.exists(source_path), f"Source file {source_path} is missing."
    assert os.path.isfile(source_path), f"{source_path} is not a file."
    with open(source_path, "r") as f:
        content = f.read()
    assert len(content.strip()) > 0, f"{source_path} is empty."
    assert "#include" in content, f"{source_path} does not look like a C program."


def test_executable_exists():
    exec_path = "/home/user/track_config"
    assert os.path.exists(exec_path), f"Executable {exec_path} is missing."
    assert os.path.isfile(exec_path), f"{exec_path} is not a file."
    assert os.access(exec_path, os.X_OK), f"{exec_path} is not executable."


def test_csv_output_correct():
    csv_path = "/home/user/latest_configs.csv"
    assert os.path.exists(csv_path), f"Output CSV {csv_path} is missing."
    assert os.path.isfile(csv_path), f"{csv_path} is not a file."

    expected_csv = """server,key,value
srv-01,DB_HOST,primary-db-v2
srv-01,WORKER_THREADS,16
srv-02,DB_HOST,replica-db
srv-02,WORKER_THREADS,8
srv-03,CACHE_SIZE,1024
srv-03,WORKER_THREADS,8"""

    with open(csv_path, "r") as f:
        actual_csv = f.read().strip()

    expected_lines = expected_csv.splitlines()
    actual_lines = actual_csv.splitlines()
    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows in CSV, got {len(actual_lines)}."
    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual.strip() == expected.strip(), f"Mismatch at row {i+1}: expected '{expected.strip()}', got '{actual.strip()}'."


def expected_lines(events):
    latest = {}
    for _, server, key, value in events:
        latest[(server, key)] = value
    return ["server,key,value"] + [
        f"{server},{key},{latest[(server, key)]}"
        for server, key in sorted(latest)
    ]


def run_case(events):
    log_path = "/home/user/config_updates.log"
    csv_path = "/home/user/latest_configs.csv"
    with open(log_path, "w") as f:
        for timestamp, server, key, value in events:
            f.write(f"[{timestamp}] {server} {key}={value}\n")

    result = subprocess.run(
        ["/home/user/track_config"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"track_config exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(csv_path), "Program did not create /home/user/latest_configs.csv."
    with open(csv_path, "r") as f:
        actual = f.read().splitlines()
    assert actual == expected_lines(events), (
        f"Incorrect CSV for generated input. Expected {expected_lines(events)!r}, got {actual!r}."
    )


def test_program_is_compiled_from_source_and_handles_generated_inputs():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "/home/user/track_config.c", "-o", "/home/user/track_config"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"track_config.c did not compile with gcc: {compile_result.stderr}"
    )

    nonce = secrets.token_hex(6)
    a = f"srv-a-{nonce}"
    b = f"srv-b-{nonce}"
    c = f"srv-c-{nonce}"
    key_a = f"ALPHA_{nonce}"
    key_m = f"MIDDLE_{nonce}"
    key_z = f"ZETA_{nonce}"

    events = [
        ("2026-01-01 00:00:00", b, key_z, f"old_{nonce}"),
        ("2026-01-01 00:01:00", a, key_m, f"first_{nonce}"),
        ("2026-01-01 00:01:00", a, key_m, f"first_{nonce}"),
        ("2026-01-01 00:02:00", c, key_a, f"only_{nonce}"),
        ("2026-01-01 00:03:00", b, key_z, f"new_{nonce}"),
        ("2026-01-01 00:04:00", a, key_a, f"alpha_{nonce}"),
        ("2026-01-01 00:05:00", b, key_a, f"bval_{nonce}"),
        ("2026-01-01 00:06:00", a, key_m, f"latest_{nonce}"),
    ]
    run_case(events)

    nonce2 = secrets.token_hex(6)
    events2 = [
        ("2026-02-02 10:00:00", f"single-{nonce2}", f"KEY_{nonce2}", f"before_{nonce2}"),
        ("2026-02-02 10:01:00", f"single-{nonce2}", f"KEY_{nonce2}", f"after_{nonce2}"),
    ]
    run_case(events2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
