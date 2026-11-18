#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile

import pytest

PIPELINE = "/home/user/pipeline"
DETECT = f"{PIPELINE}/detect.sh"
SWEEP = f"{PIPELINE}/sweep.sh"
CSV_PATH = f"{PIPELINE}/sensor_data.csv"
JSON_PATH = f"{PIPELINE}/experiments.json"


def round_half_up(n):
    return math.floor(n + 0.5)


def expected_counts(rows):
    values = [float(v) for v in rows if v != ""]
    assert values, "Test data must contain non-missing values."
    mean = round_half_up(sum(values) / len(values))
    imputed = [mean if v == "" else float(v) for v in rows]
    mad = round_half_up(sum(abs(v - mean) for v in imputed) / len(imputed))
    return {
        threshold: sum(1 for v in imputed if abs(v - mean) > threshold * mad)
        for threshold in range(1, 6)
    }


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "value"])
        for i, value in enumerate(rows, 1):
            writer.writerow([i, value])
    os.chmod(path, 0o644)


def run_as_user(argv, timeout=20):
    return subprocess.run(
        ["sudo", "-u", "user", "--"] + list(argv),
        cwd=PIPELINE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def assert_json_correct(path, rows, expected_time=None):
    assert os.path.isfile(path), f"{path} is missing."
    try:
        with open(path) as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{path} does not contain valid JSON.")

    assert isinstance(data, list), "experiments.json should contain a JSON array."
    assert len(data) == 5, f"experiments.json should contain exactly 5 results, found {len(data)}."
    expected = expected_counts(rows)
    thresholds_found = set()

    for item in data:
        assert "threshold" in item, "Missing 'threshold' key in JSON object."
        assert "anomalies" in item, "Missing 'anomalies' key in JSON object."
        assert "time_ms" in item, "Missing 'time_ms' key in JSON object."
        threshold = item["threshold"]
        thresholds_found.add(threshold)
        assert threshold in expected, f"Unexpected threshold {threshold} found in JSON."
        assert item["anomalies"] == expected[threshold], (
            f"Incorrect anomalies count for threshold {threshold}. "
            f"Expected {expected[threshold]}, got {item['anomalies']}."
        )
        assert isinstance(item["time_ms"], int), f"time_ms should be an integer for threshold {threshold}."
        assert item["time_ms"] >= 0, f"time_ms should be non-negative for threshold {threshold}."
        if expected_time is not None:
            assert item["time_ms"] == expected_time, (
                f"time_ms for threshold {threshold} was not computed from the required before/after timestamps."
            )

    assert thresholds_found == {1, 2, 3, 4, 5}, (
        "JSON must contain exactly results for thresholds 1, 2, 3, 4, and 5."
    )


def read_csv_values(path):
    rows = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row["value"].strip())
    return rows


def test_dependencies_installed():
    assert shutil.which("datamash") is not None, "datamash is not installed on the system."
    assert shutil.which("jq") is not None, "jq is not installed on the system."


def test_scripts_exist_and_executable():
    assert os.path.isfile(DETECT), f"{DETECT} is missing."
    assert os.access(DETECT, os.X_OK), f"{DETECT} is not executable."
    assert os.path.isfile(SWEEP), f"{SWEEP} is missing."
    assert os.access(SWEEP, os.X_OK), f"{SWEEP} is not executable."


def test_detect_executes_correctly_on_unseen_inputs():
    rng = random.SystemRandom()
    for case in range(3):
        rows = [str(rng.randint(-150, 250)) for _ in range(15)]
        for index in rng.sample(range(len(rows)), 3):
            rows[index] = ""
        threshold = rng.randint(1, 5)
        expected = expected_counts(rows)[threshold]

        fd, path = tempfile.mkstemp(prefix="detect_input_", suffix=".csv")
        os.close(fd)
        try:
            write_csv(path, rows)
            result = run_as_user([DETECT, path, str(threshold)])
            assert result.returncode == 0, f"detect.sh failed: {result.stderr}"
            assert re.fullmatch(r"[0-9]+\n?", result.stdout), (
                "detect.sh must print only the integer anomaly count."
            )
            assert int(result.stdout.strip()) == expected, (
                f"detect.sh returned the wrong result for generated case {case}."
            )
        finally:
            os.unlink(path)


def test_sweep_runs_detect_and_benchmarks_each_call():
    rng = random.SystemRandom()
    rows = [str(rng.randint(-200, 300)) for _ in range(18)]
    for index in rng.sample(range(len(rows)), 4):
        rows[index] = ""

    original_csv = open(CSV_PATH, "rb").read()
    original_detect = open(DETECT, "rb").read()
    detect_stat = os.stat(DETECT)

    date_path = os.path.realpath(shutil.which("date"))
    original_date = open(date_path, "rb").read()
    date_stat = os.stat(date_path)

    saved_detect = "/tmp/verifier_original_detect.sh"
    events = "/tmp/verifier_sweep_events"
    counter = "/tmp/verifier_date_counter"
    open(saved_detect, "wb").write(original_detect)
    os.chmod(saved_detect, detect_stat.st_mode)
    open(events, "w").close()
    open(counter, "w").write("0\n")
    os.chmod(events, 0o666)
    os.chmod(counter, 0o666)

    detect_wrapper = f'''#!/bin/bash
printf 'T\\t%s\\t%s\\n' "$1" "$2" >> {events}
exec {saved_detect} "$@"
'''.encode()
    date_wrapper = f'''#!/bin/bash
if [ "$#" -eq 1 ] && [ "$1" = "+%s%3N" ]; then
    n=$(cat {counter})
    n=$((n + 1))
    printf '%s\\n' "$n" > {counter}
    printf 'D\\n' >> {events}
    printf '%s\\n' $((100000 + n * 17))
else
    exec /tmp/verifier_real_date "$@"
fi
'''.encode()

    open("/tmp/verifier_real_date", "wb").write(original_date)
    os.chmod("/tmp/verifier_real_date", date_stat.st_mode)

    try:
        write_csv(CSV_PATH, rows)
        open(DETECT, "wb").write(detect_wrapper)
        os.chmod(DETECT, 0o755)
        open(date_path, "wb").write(date_wrapper)
        os.chmod(date_path, 0o755)
        if os.path.exists(JSON_PATH):
            os.unlink(JSON_PATH)

        result = run_as_user([SWEEP], timeout=30)
        assert result.returncode == 0, f"sweep.sh failed: {result.stderr}"
        assert_json_correct(JSON_PATH, rows, expected_time=17)

        with open(events) as f:
            event_lines = [line.rstrip("\n") for line in f]
        assert len(event_lines) == 15, (
            "sweep.sh must take one timestamp before and after each of five detect.sh calls."
        )
        called_thresholds = []
        for i in range(0, 15, 3):
            assert event_lines[i] == "D" and event_lines[i + 2] == "D", (
                "Each detect.sh call must be bracketed by date +%s%3N calls."
            )
            fields = event_lines[i + 1].split("\t")
            assert len(fields) == 3 and fields[0] == "T", "sweep.sh did not invoke detect.sh correctly."
            assert os.path.realpath(fields[1]) == os.path.realpath(CSV_PATH), (
                "sweep.sh must pass sensor_data.csv to detect.sh."
            )
            called_thresholds.append(int(fields[2]))
        assert set(called_thresholds) == {1, 2, 3, 4, 5}, (
            "sweep.sh must call detect.sh once for every threshold from 1 through 5."
        )
    finally:
        open(date_path, "wb").write(original_date)
        os.chmod(date_path, stat.S_IMODE(date_stat.st_mode))
        os.chown(date_path, date_stat.st_uid, date_stat.st_gid)
        open(DETECT, "wb").write(original_detect)
        os.chmod(DETECT, stat.S_IMODE(detect_stat.st_mode))
        os.chown(DETECT, detect_stat.st_uid, detect_stat.st_gid)
        open(CSV_PATH, "wb").write(original_csv)
        os.chown(CSV_PATH, 1000, 1000)
        os.chmod(CSV_PATH, 0o666)

    # Run the submitted artifacts normally so the required final output is produced
    # from the original sensor data, then retain the original final-state assertions.
    original_rows = read_csv_values(CSV_PATH)
    result = run_as_user([SWEEP], timeout=30)
    assert result.returncode == 0, f"sweep.sh failed on sensor_data.csv: {result.stderr}"
    assert_json_correct(JSON_PATH, original_rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
