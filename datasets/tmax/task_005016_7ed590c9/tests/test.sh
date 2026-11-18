#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile

CONFIG = "/home/user/config/collector.conf"
SCRIPT = "/home/user/aggregate.sh"
METRIC = "/home/user/final_metric.txt"
DATA = "/home/user/data"
WAL = os.path.join(DATA, "wal.txt")


def test_config_file_created():
    assert os.path.isfile(CONFIG), f"Configuration file {CONFIG} was not created."

    with open(CONFIG, "rb") as f:
        content = f.read()

    assert content in (b"ENABLE_PROFILING=true", b"ENABLE_PROFILING=true\n"), (
        f"Expected {CONFIG} to contain exactly one line, "
        f"'ENABLE_PROFILING=true', but found: {content!r}"
    )


def test_final_metric_correct():
    assert os.path.isfile(METRIC), f"Output file {METRIC} was not created."

    with open(METRIC, "rb") as f:
        raw = f.read()

    assert raw in (b"20", b"20\n"), (
        f"Expected final metric to be exactly '20' on one line, but got {raw!r}. "
        "Ensure spaces in filenames are handled, only committed WAL transactions are processed, "
        "and the latency formula multiplies by 1000 before dividing."
    )


def _has_uncommitted_metrics(path):
    if not os.path.isfile(path):
        return False
    active = False
    pending_metrics = False
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if line.startswith("BEGIN "):
                active = True
                pending_metrics = False
            elif active and (line.startswith("REQS=") or line.startswith("LATENCY=")):
                pending_metrics = True
            elif line.startswith("COMMIT ") and active:
                active = False
                pending_metrics = False
    return active and pending_metrics


def test_aggregate_executes_and_processes_dynamic_inputs():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} does not exist."
    st = os.stat(SCRIPT)
    assert stat.S_ISREG(st.st_mode), f"{SCRIPT} is not a regular file."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."

    # If the submitted solution retained an uncommitted tail, the script must
    # filter it. A solution that repaired the WAL directly is also permitted by
    # the instruction, so its dynamic fixtures contain only committed records.
    must_filter_uncommitted = _has_uncommitted_metrics(WAL)

    parent = os.path.dirname(DATA)
    backup_root = tempfile.mkdtemp(prefix="verifier-data-", dir=parent)
    backup_data = os.path.join(backup_root, "data")
    os.rename(DATA, backup_data)

    rng = random.SystemRandom()
    try:
        for case in range(3):
            os.mkdir(DATA)

            while True:
                logs = [
                    (rng.randint(70, 190), rng.randint(2, 9)),
                    (rng.randint(80, 210), rng.randint(2, 10)),
                    (rng.randint(60, 170), rng.randint(1, 8)),
                ]
                committed = (rng.randint(35, 95), rng.randint(2, 11))
                uncommitted = (rng.randint(4000, 9000), rng.randint(3000, 8000))
                log_reqs = sum(x[0] for x in logs)
                log_latency = sum(x[1] for x in logs)
                expected = ((log_latency + committed[1]) * 1000) // (log_reqs + committed[0])
                logs_only = (log_latency * 1000) // log_reqs
                with_uncommitted = (
                    (log_latency + committed[1] + uncommitted[1]) * 1000
                ) // (log_reqs + committed[0] + uncommitted[0])
                if expected > 0 and expected != 20 and expected != logs_only and (
                    not must_filter_uncommitted or expected != with_uncommitted
                ):
                    break

            token = f"{rng.getrandbits(64):016x}"
            names = [
                f"frontend node {token}.log",
                f"backend worker {token}.log",
                f"third server {token}.log",
            ]
            for name, (reqs, latency) in zip(names, logs):
                with open(os.path.join(DATA, name), "w", encoding="utf-8") as f:
                    f.write(f"REQS={reqs}\nLATENCY={latency}\n")

            with open(WAL, "w", encoding="utf-8") as f:
                f.write(
                    f"BEGIN TX {token}\n"
                    f"REQS={committed[0]}\n"
                    f"LATENCY={committed[1]}\n"
                    f"COMMIT TX {token}\n"
                )
                if must_filter_uncommitted:
                    f.write(
                        f"BEGIN TX partial-{token}\n"
                        f"REQS={uncommitted[0]}\n"
                        f"LATENCY={uncommitted[1]}\n"
                    )

            result = subprocess.run(
                [SCRIPT],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
                check=False,
            )
            assert result.returncode == 0, (
                f"{SCRIPT} failed on dynamic case {case}: {result.stderr}"
            )
            assert re.fullmatch(r"-?[0-9]+\n?", result.stdout), (
                f"Expected exactly one integer on stdout, got {result.stdout!r}"
            )
            actual = int(result.stdout.strip())
            assert actual == expected, (
                f"Dynamic case {case} expected {expected}, got {actual}. "
                "The script must handle spaces in every .log filename, include committed WAL "
                "metrics, exclude any retained uncommitted tail, and multiply by 1000 before division."
            )

            shutil.rmtree(DATA)
    finally:
        if os.path.exists(DATA):
            shutil.rmtree(DATA)
        os.rename(backup_data, DATA)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
