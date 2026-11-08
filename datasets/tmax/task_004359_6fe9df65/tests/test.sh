#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import stat
import subprocess
import tempfile
import pytest

ROOT = "/app/cJSON-1.7.15"
EXE = "/home/user/config_tracker"
SCRIPT = "/home/user/process_logs.sh"


def run_tracker(records):
    with tempfile.TemporaryDirectory(prefix="tracker_test_") as d:
        inp = os.path.join(d, "input.jsonl")
        out = os.path.join(d, "output.csv")
        with open(inp, "w") as f:
            for record in records:
                f.write(json.dumps(record, separators=(",", ":")) + "\n")
        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = ROOT + ":" + env.get("LD_LIBRARY_PATH", "")
        try:
            subprocess.run([EXE, inp, out], env=env, check=True, timeout=10,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program failed: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail("Agent program timed out")
        assert os.path.isfile(out), "output CSV was not created"
        with open(out, newline="") as f:
            rows = list(csv.DictReader(f))
        assert rows or not records, "output CSV has no data rows"
        if not records:
            with open(out, newline="") as f:
                assert next(csv.reader(f), None) == ["timestamp", "z_score"]
        return rows


def expected(records):
    sizes = []
    result = []
    for r in records:
        sizes.append(r["size"])
        window = sizes[-10:]
        mean = sum(window) / len(window)
        variance = sum((x - mean) ** 2 for x in window) / len(window)
        std = math.sqrt(variance)
        z = 0.0 if std == 0 else (r["size"] - mean) / std
        result.append((str(r["timestamp"]), z))
    return result


def assert_results(records):
    rows = run_tracker(records)
    assert len(rows) == len(records), "wrong number of output rows"
    assert set(rows[0].keys()) == {"timestamp", "z_score"} if rows else True
    for i, (row, (ts, z)) in enumerate(zip(rows, expected(records))):
        assert row["timestamp"] == ts, f"timestamp mismatch at row {i}"
        assert row["z_score"] == f"{z:.6f}", f"incorrect six-decimal Z-score at row {i}"


def test_cjson_makefile_and_build():
    makefile = os.path.join(ROOT, "Makefile")
    assert os.path.isfile(makefile), "cJSON Makefile missing"
    text = open(makefile).read()
    assert "-fPIC" in text, "Makefile was not fixed to use -fPIC"
    subprocess.run(["make", "clean"], cwd=ROOT, check=True, timeout=30,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(["make", "cJSON.so"], cwd=ROOT, check=True, timeout=60,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lib = os.path.join(ROOT, "libcjson.so")
    assert os.path.isfile(lib), "libcjson.so was not built"
    elf = subprocess.check_output(["file", lib], text=True)
    assert "shared object" in elf, "libcjson.so is not a shared library"


def test_executable_and_cjson_linkage():
    assert os.path.isfile("/home/user/config_tracker.c"), "config_tracker.c missing"
    assert os.path.isfile(EXE), "config_tracker missing"
    assert os.access(EXE, os.X_OK), "config_tracker is not executable"
    assert open(EXE, "rb").read(4) == b"\x7fELF", "config_tracker is not a compiled executable"
    dynamic = subprocess.check_output(["readelf", "-d", EXE], text=True)
    assert "libcjson.so" in dynamic, "config_tracker is not linked against libcjson.so"


def test_tracker_on_fresh_derived_inputs():
    rng = random.SystemRandom()
    token = rng.randrange(10**8, 10**9)
    sizes = [rng.randrange(-5000, 9000) for _ in range(27)]
    sizes[0:3] = [777, 777, 777]
    records = [{"file": f"odd file {i}.conf", "size": size,
                "timestamp": token + i * 13} for i, size in enumerate(sizes)]
    assert_results(records)


def test_global_window_across_files_and_rollover():
    base = random.SystemRandom().randrange(2_000_000_000, 2_100_000_000)
    sizes = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 1000, -250, 333]
    records = [{"size": x, "timestamp": base + i,
                "file": "A" if i % 2 == 0 else "B"} for i, x in enumerate(sizes)]
    assert_results(records)


def test_process_logs_script_behavior():
    assert os.path.isfile(SCRIPT), "process_logs.sh missing"
    assert os.access(SCRIPT, os.X_OK), "process_logs.sh is not executable"
    sample = "/home/user/config_logs.jsonl"
    output = "/home/user/anomalies.csv"
    backup = None
    if os.path.exists(output):
        backup = open(output, "rb").read()
    try:
        if os.path.exists(output):
            os.remove(output)
        env = os.environ.copy()
        env.pop("LD_LIBRARY_PATH", None)
        subprocess.run([SCRIPT], env=env, check=True, timeout=15,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert os.path.isfile(output), "pipeline script did not create anomalies.csv"
        records = [json.loads(line) for line in open(sample) if line.strip()]
        with open(output, newline="") as f:
            rows = list(csv.DictReader(f))
        assert len(rows) == len(records)
        for row, (ts, z) in zip(rows, expected(records)):
            assert row["timestamp"] == ts
            assert row["z_score"] == f"{z:.6f}"
    finally:
        if backup is not None:
            open(output, "wb").write(backup)


def test_cron_job():
    try:
        lines = subprocess.check_output(["crontab", "-l", "-u", "user"], text=True).splitlines()
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read user crontab")
    active = [line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#")]
    assert any(line.split()[:5] == ["*/5", "*", "*", "*", "*"] and
               "/home/user/process_logs.sh" in " ".join(line.split()[5:])
               for line in active), "missing every-five-minutes process_logs.sh cron job"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
