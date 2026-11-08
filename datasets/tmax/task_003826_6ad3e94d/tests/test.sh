#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import signal
import stat
import subprocess
from decimal import Decimal

SCRIPT = "/home/user/aggregate.sh"
METRICS = "/home/user/metrics.csv"
RESULTS = "/home/user/results.txt"


def expected_from_csv(data):
    total_cpu = Decimal("0")
    total_mem = Decimal("0")
    count = 0

    reader = csv.DictReader(io.StringIO(data.decode("utf-8")))
    for row in reader:
        if not row:
            continue
        cpu = Decimal(row["cpu_usage"])
        mem = Decimal(row["mem_usage"])
        if cpu == Decimal("99.9"):
            cpu = Decimal("100.0")
        total_cpu += cpu
        total_mem += mem
        count += 1

    assert count > 0, "No data found in metrics.csv"
    return f"{total_cpu / count:.3f}", f"{total_mem / count:.3f}"


def run_script():
    if os.path.lexists(RESULTS):
        os.remove(RESULTS)

    proc = subprocess.Popen(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise AssertionError("aggregate.sh did not terminate within 5 seconds")

    assert proc.returncode == 0, (
        f"aggregate.sh exited with status {proc.returncode}\n"
        f"stdout: {stdout}\nstderr: {stderr}"
    )
    assert os.path.exists(RESULTS), f"Output file {RESULTS} does not exist. Did the script create it?"
    assert os.path.isfile(RESULTS), f"{RESULTS} is not a file."


def validate_results(metrics_data):
    expected_cpu, expected_mem = expected_from_csv(metrics_data)
    with open(RESULTS, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, f"Expected exactly 2 lines in {RESULTS}, got {len(lines)}"
    assert lines[0] == f"AvgCPU: {expected_cpu}", (
        f"Expected first line 'AvgCPU: {expected_cpu}', got '{lines[0]}'"
    )
    assert lines[1] == f"AvgMem: {expected_mem}", (
        f"Expected second line 'AvgMem: {expected_mem}', got '{lines[1]}'"
    )


def test_aggregate_script_end_to_end():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} is missing."
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} is not a regular file."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."
    assert os.path.exists(METRICS), f"{METRICS} is missing."

    with open(METRICS, "rb") as f:
        original_metrics = f.read()

    rng = random.SystemRandom()
    cpus = [f"{rng.randint(101, 850) / 10:.1f}" for _ in range(3)]
    mems = [rng.randint(700, 3500) for _ in range(4)]
    alternate_metrics = (
        "timestamp,cpu_usage,mem_usage\n"
        f"2001,{cpus[0]},{mems[0]}\n"
        f"2002,99.9,{mems[1]}\n"
        f"2003,{cpus[1]},{mems[2]}\n"
        f"2004,{cpus[2]},{mems[3]}\n"
    ).encode("utf-8")

    try:
        run_script()
        validate_results(original_metrics)

        with open(METRICS, "wb") as f:
            f.write(alternate_metrics)
        run_script()
        validate_results(alternate_metrics)
    finally:
        with open(METRICS, "wb") as f:
            f.write(original_metrics)
        run_script()

    validate_results(original_metrics)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
