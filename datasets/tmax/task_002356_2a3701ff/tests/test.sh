#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import random
import re
import secrets
import stat
import subprocess
import tempfile
import pytest

HOME = "/home/user"
RAW = f"{HOME}/raw_sensor_data.csv"


def parse_and_clean_data(raw_path):
    """Helper to compute expected clean data based on task rules."""
    expected_clean = []
    with open(raw_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        expected_clean.append(header)
        for row in reader:
            if len(row) != 4:
                continue
            ts, sid, temp, hum = row
            try:
                sid = int(sid)
                temp = float(temp)
                hum = float(hum)
            except ValueError:
                continue

            if not (-50.0 <= temp <= 50.0):
                continue
            if not (0.0 <= hum <= 100.0):
                continue

            expected_clean.append(row)
    return expected_clean


def compute_anomalies(clean_data):
    """Helper to compute expected anomalies based on Bayesian model rules."""
    header = clean_data[0]
    rows = clean_data[1:]
    sensors = {}
    for row in rows:
        sid = int(row[1])
        temp = float(row[2])
        sensors.setdefault(sid, []).append((temp, row))

    mu_0 = 20.0
    var_0 = 25.0
    var_like = 4.0
    expected_anomalies = [header]

    for sid, readings in sensors.items():
        n = len(readings)
        sum_x = sum(t for t, r in readings)
        inv_var_post = (1.0 / var_0) + (n / var_like)
        var_post = 1.0 / inv_var_post
        mu_post = var_post * ((mu_0 / var_0) + (sum_x / var_like))
        std_pred = math.sqrt(var_post + var_like)
        threshold = 3.0 * std_pred
        for temp, row in readings:
            if abs(temp - mu_post) > threshold:
                expected_anomalies.append(row)
    return expected_anomalies


def read_benchmark():
    path = f"{HOME}/benchmark.txt"
    assert os.path.exists(path), f"Missing output file: {path}"
    content = open(path).read().strip()
    assert re.fullmatch(r"(?:0|[1-9][0-9]*)\.[0-9]{2}", content), \
        "benchmark.txt must contain one value rounded to exactly two decimal places"
    value = float(content)
    assert value > 0.0, "Benchmark time should be strictly positive."
    return value


def benchmark_loop_lines(path):
    source = open(path, encoding="utf-8").read()
    tree = ast.parse(source, filename=path)
    constants = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if isinstance(value, ast.Constant) and isinstance(value.value, int):
                for target in targets:
                    if isinstance(target, ast.Name):
                        constants[target.id] = value.value

    def integer(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, int):
            return node.value
        if isinstance(node, ast.Name):
            return constants.get(node.id)
        return None

    lines = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.For) and isinstance(node.iter, ast.Call):
            call = node.iter
            if isinstance(call.func, ast.Name) and call.func.id == "range":
                args = [integer(a) for a in call.args]
                if all(v is not None for v in args):
                    try:
                        if len(range(*args)) == 100 and node.body:
                            lines.add(node.body[0].lineno)
                    except (TypeError, ValueError):
                        pass
        elif isinstance(node, ast.While) and node.body:
            for part in ast.walk(node.test):
                if isinstance(part, ast.Constant) and part.value == 100:
                    lines.add(node.body[0].lineno)
    return sorted(lines)


def make_dataset(path, ordinary_count, seed):
    rng = random.Random(seed)
    rows = [["timestamp", "sensor_id", "temperature", "humidity"]]
    sensor_means = {101: 18.0, 207: 23.0, 319: 12.0, 421: 27.0}
    sensor_ids = list(sensor_means)
    for i in range(ordinary_count):
        sid = sensor_ids[i % len(sensor_ids)]
        temp = round(rng.gauss(sensor_means[sid], 1.15), 2)
        hum = round(35.0 + ((i * 17) % 5000) / 100.0, 2)
        rows.append([f"2026-08-01T{i // 60:02d}:{i % 60:02d}:00Z", sid, temp, hum])

    # Clear anomalies and independently derived schema-invalid records.
    rows.extend([
        ["2026-08-03T00:00:00Z", 101, 42.37, 45.0],
        ["2026-08-03T00:01:00Z", 207, -8.43, 55.0],
        ["2026-08-03T00:02:00Z", 319, 39.91, 50.0],
        ["bad-type", "not_an_integer", 20.0, 50.0],
        ["bad-temperature", 101, "invalid_float", 50.0],
        ["bad-low-temperature", 207, -50.01, 50.0],
        ["bad-high-temperature", 207, 50.01, 50.0],
        ["bad-humidity", 319, 20.0, 100.01],
        ["missing", 421, "", 40.0],
    ])
    with open(path, "w", newline="") as f:
        csv.writer(f).writerows(rows)


def validate_current_outputs():
    expected_clean = parse_and_clean_data(RAW)
    with open(f"{HOME}/clean_data.csv", newline="") as f:
        actual_clean = list(csv.reader(f))
    assert actual_clean == expected_clean, "clean_data.csv content does not match expected cleaned data."

    expected_anomalies = compute_anomalies(expected_clean)
    with open(f"{HOME}/anomalies.csv", newline="") as f:
        actual_anomalies = list(csv.reader(f))
    assert actual_anomalies, "anomalies.csv is empty"
    assert actual_anomalies[0] == expected_anomalies[0], "Header mismatch in anomalies.csv"
    assert {tuple(r) for r in actual_anomalies[1:]} == {tuple(r) for r in expected_anomalies[1:]}, \
        "Data rows in anomalies.csv do not match expected anomalies."


def test_required_artifacts_and_execute_pipeline():
    scripts = [f"{HOME}/step1_clean.py", f"{HOME}/step2_inference.py", f"{HOME}/step3_benchmark.py"]
    pipeline = f"{HOME}/run_pipeline.sh"
    for path in scripts + [pipeline]:
        assert os.path.isfile(path), f"Missing regular file: {path}"
        assert os.path.getsize(path) > 0, f"Empty required file: {path}"
    for path in scripts:
        ast.parse(open(path, encoding="utf-8").read(), filename=path)
    assert os.stat(pipeline).st_mode & stat.S_IXUSR, f"Script {pipeline} is not executable."

    loop_lines = benchmark_loop_lines(scripts[2])
    assert loop_lines, "step3_benchmark.py has no identifiable loop of exactly 100 iterations"

    marker = tempfile.mktemp(prefix="pipeline_markers_")
    timing = tempfile.mktemp(prefix="benchmark_trace_")
    saved = []
    original_raw = open(RAW, "rb").read()

    try:
        for index, path in enumerate(scripts, 1):
            backup = tempfile.mktemp(prefix=f"saved_step{index}_", suffix=".py")
            os.rename(path, backup)
            saved.append((path, backup))
            mode = os.stat(backup).st_mode

            if index != 3:
                wrapper = f'''#!/usr/bin/env python3
import runpy
with open({marker!r}, "a") as f:
    f.write({str(index)!r} + "\\n")
runpy.run_path({backup!r}, run_name="__main__")
'''
            else:
                wrapper = f'''#!/usr/bin/env python3
import json, runpy, sys, time
counts = {{line: [0, None, None] for line in {loop_lines!r}}}
def trace(frame, event, arg):
    if event == "line" and frame.f_code.co_filename == {backup!r} and frame.f_lineno in counts:
        now = time.perf_counter()
        item = counts[frame.f_lineno]
        item[0] += 1
        if item[1] is None:
            item[1] = now
        item[2] = now
    return trace
with open({marker!r}, "a") as f:
    f.write("3\\n")
sys.settrace(trace)
try:
    runpy.run_path({backup!r}, run_name="__main__")
finally:
    sys.settrace(None)
    with open({timing!r}, "a") as f:
        f.write(json.dumps(counts) + "\\n")
'''
            with open(path, "w") as f:
                f.write(wrapper)
            os.chmod(path, mode)

        values = []
        seed = secrets.randbits(64)
        for run_number, size in enumerate((80, 1600)):
            make_dataset(RAW, size, seed + run_number)
            for output in ("clean_data.csv", "anomalies.csv", "benchmark.txt"):
                try:
                    os.remove(f"{HOME}/{output}")
                except FileNotFoundError:
                    pass
            open(marker, "w").close()
            open(timing, "w").close()
            result = subprocess.run(
                [pipeline], cwd=HOME, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, timeout=120
            )
            assert result.returncode == 0, f"run_pipeline.sh failed:\n{result.stdout}"
            assert open(marker).read().splitlines() == ["1", "2", "3"], \
                "run_pipeline.sh must sequentially execute step1_clean.py, step2_inference.py, and step3_benchmark.py"
            validate_current_outputs()
            value = read_benchmark()
            values.append(value)

            records = [json.loads(line) for line in open(timing) if line.strip()]
            assert len(records) == 1, "step3_benchmark.py was not executed exactly once by the pipeline"
            observations = []
            for count, first, last in records[0].values():
                if count >= 100 and first is not None and last is not None:
                    observations.append(((last - first) * 1000.0) / max(count - 1, 1))
            assert observations, "the 100-iteration benchmark loop was not actually executed"
            assert value <= max(observations) * 5.0 + 0.05, \
                "benchmark.txt is not plausible for the measured 100-iteration loop"

        assert values[1] > values[0], \
            "benchmark must measure inference over the entire dataset; it did not increase for a much larger dataset"
    finally:
        for path, backup in reversed(saved):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
            if os.path.exists(backup):
                os.rename(backup, path)
        with open(RAW, "wb") as f:
            f.write(original_raw)
        for path in (marker, timing):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_pipeline_script_exists_and_executable():
    """Check if run_pipeline.sh exists and is executable."""
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.exists(script_path), f"Missing script: {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_clean_data_correctness():
    """Validate clean_data.csv against expected task logic."""
    clean_path = "/home/user/clean_data.csv"
    assert os.path.exists(clean_path), f"Missing output file: {clean_path}"
    expected_clean = parse_and_clean_data(RAW)
    with open(clean_path, 'r', newline='') as f:
        actual_clean = list(csv.reader(f))
    assert len(actual_clean) == len(expected_clean), f"Expected {len(expected_clean)} rows in clean_data.csv, got {len(actual_clean)}"
    assert actual_clean == expected_clean, "clean_data.csv content does not match expected cleaned data."


def test_anomalies_correctness():
    """Validate anomalies.csv against expected Bayesian anomaly logic."""
    anomalies_path = "/home/user/anomalies.csv"
    assert os.path.exists(anomalies_path), f"Missing output file: {anomalies_path}"
    expected_anomalies = compute_anomalies(parse_and_clean_data(RAW))
    with open(anomalies_path, 'r', newline='') as f:
        actual_anomalies = list(csv.reader(f))
    assert len(actual_anomalies) == len(expected_anomalies), f"Expected {len(expected_anomalies)} rows in anomalies.csv, got {len(actual_anomalies)}"
    assert actual_anomalies[0] == expected_anomalies[0], "Header mismatch in anomalies.csv"
    assert {tuple(r) for r in actual_anomalies[1:]} == {tuple(r) for r in expected_anomalies[1:]}, \
        "Data rows in anomalies.csv do not match expected anomalies."


def test_benchmark_output():
    """Validate benchmark.txt exists and contains a parseable positive float."""
    benchmark_path = "/home/user/benchmark.txt"
    assert os.path.exists(benchmark_path), f"Missing output file: {benchmark_path}"
    content = open(benchmark_path).read().strip()
    assert content, "benchmark.txt is empty."
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse benchmark.txt content as float: '{content}'")
    assert val > 0.0, "Benchmark time should be strictly positive."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
