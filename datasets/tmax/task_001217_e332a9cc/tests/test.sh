#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import re
import random
import uuid


def test_files_exist_and_permissions():
    assert os.path.exists("/home/user/analyzer.cpp"), "/home/user/analyzer.cpp does not exist."
    assert os.path.exists("/home/user/optimizer.sh"), "/home/user/optimizer.sh does not exist."
    assert os.path.exists("/home/user/finops.cron"), "/home/user/finops.cron does not exist."
    assert os.path.isfile("/home/user/analyzer.cpp"), "/home/user/analyzer.cpp is not a regular file."
    assert os.path.isfile("/home/user/optimizer.sh"), "/home/user/optimizer.sh is not a regular file."

    st = os.stat("/home/user/optimizer.sh")
    assert bool(st.st_mode & stat.S_IXUSR), "/home/user/optimizer.sh is not executable."


def test_cron_configuration():
    with open("/home/user/finops.cron", "r") as f:
        content = f.read().strip()

    pattern = r"^0+\s+0*2\s+\*\s+\*\s+\*\s+/home/user/optimizer\.sh$"
    match = False
    for line in content.splitlines():
        line = line.strip()
        if re.match(pattern, line):
            match = True
            break

    assert match, "finops.cron does not contain the correct cron expression for 2:00 AM running /home/user/optimizer.sh."


def expected_ids(rows):
    return [container_id for container_id, cpu, memory in rows if cpu < 5.0 and memory < 50.0]


def write_metrics(path, rows):
    with open(path, "w") as f:
        for container_id, cpu, memory in rows:
            f.write(f"{container_id},{cpu},{memory}\n")


def make_unpredictable_rows():
    rng = random.SystemRandom()
    rows = [
        ("idle-" + uuid.uuid4().hex, rng.uniform(-3.0, 4.8), rng.uniform(0.0, 49.8)),
        ("cpu-boundary-" + uuid.uuid4().hex, 5.0, rng.uniform(0.0, 49.0)),
        ("mem-boundary-" + uuid.uuid4().hex, rng.uniform(-2.0, 4.9), 50.0),
        ("busy-" + uuid.uuid4().hex, rng.uniform(5.1, 90.0), rng.uniform(50.1, 5000.0)),
    ]
    for _ in range(12):
        rows.append((uuid.uuid4().hex, rng.uniform(-5.0, 15.0), rng.uniform(0.0, 100.0)))
    rng.shuffle(rows)
    return rows


def test_analyzer_compiles_and_handles_unpredictable_inputs():
    binary = "/tmp/verifier_analyzer"
    result = subprocess.run(
        ["g++", "/home/user/analyzer.cpp", "-o", binary],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"analyzer.cpp did not compile. stderr: {result.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Compiled analyzer is not executable."

    for index in range(2):
        rows = make_unpredictable_rows()
        metrics = f"/tmp/verifier_metrics_{index}.csv"
        write_metrics(metrics, rows)
        run = subprocess.run([binary, metrics], capture_output=True, text=True)
        assert run.returncode == 0, f"Analyzer failed with exit code {run.returncode}. stderr: {run.stderr}"
        assert run.stdout.splitlines() == expected_ids(rows), (
            f"Analyzer output was incorrect for verifier-generated input. Got: {run.stdout.splitlines()}"
        )
        assert run.stderr == "", f"Analyzer wrote unexpected stderr: {run.stderr}"


def test_optimizer_execution_and_logic():
    metrics_path = "/home/user/metrics.csv"
    log_path = "/home/user/stopped_containers.log"
    analyzer_bin = "/home/user/analyzer"

    metrics_content = """c-web-01,45.2,1024.0
c-cache-02,1.2,30.5
c-db-03,3.0,150.0
c-worker-04,0.5,10.0
c-proxy-05,4.9,49.9
c-job-06,5.1,10.0"""
    with open(metrics_path, "w") as f:
        f.write(metrics_content)

    if os.path.exists(log_path):
        os.remove(log_path)
    if os.path.exists(analyzer_bin):
        os.remove(analyzer_bin)

    result = subprocess.run(["/home/user/optimizer.sh"], capture_output=True, text=True)
    assert result.returncode == 0, f"optimizer.sh failed with exit code {result.returncode}. stderr: {result.stderr}"

    assert os.path.exists(log_path), f"{log_path} was not created."
    with open(log_path, "r") as f:
        log_content = f.read().strip().splitlines()

    expected_log = [
        "STOPPED: c-cache-02",
        "STOPPED: c-worker-04",
        "STOPPED: c-proxy-05"
    ]
    assert log_content == expected_log, f"Log contents do not match expected output. Got: {log_content}"

    os.remove(metrics_path)
    result_missing = subprocess.run(["/home/user/optimizer.sh"], capture_output=True, text=True)
    assert result_missing.returncode == 1, f"optimizer.sh should exit with code 1 when metrics.csv is missing, got {result_missing.returncode}."

    with open(metrics_path, "w") as f:
        f.write(metrics_content)


def test_optimizer_with_unpredictable_metrics_and_compiled_artifact():
    metrics_path = "/home/user/metrics.csv"
    log_path = "/home/user/stopped_containers.log"
    analyzer_bin = "/home/user/analyzer"
    rows = make_unpredictable_rows()
    expected = expected_ids(rows)
    write_metrics(metrics_path, rows)

    if os.path.exists(log_path):
        os.remove(log_path)
    if os.path.exists(analyzer_bin):
        os.remove(analyzer_bin)

    result = subprocess.run(["/home/user/optimizer.sh"], capture_output=True, text=True)
    assert result.returncode == 0, f"optimizer.sh failed on verifier-generated metrics. stderr: {result.stderr}"
    assert os.path.isfile(analyzer_bin), "optimizer.sh did not create /home/user/analyzer."
    assert os.access(analyzer_bin, os.X_OK), "/home/user/analyzer is not executable."
    assert os.path.exists(log_path), "optimizer.sh did not create the stopped-containers log."

    with open(log_path, "r") as f:
        actual_log = f.read().splitlines()
    assert actual_log == [f"STOPPED: {container_id}" for container_id in expected], (
        f"Optimizer log was incorrect for verifier-generated metrics. Got: {actual_log}"
    )

    direct = subprocess.run([analyzer_bin, metrics_path], capture_output=True, text=True)
    assert direct.returncode == 0, f"The analyzer produced by optimizer.sh failed. stderr: {direct.stderr}"
    assert direct.stdout.splitlines() == expected, "The analyzer produced by optimizer.sh is not functional."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
