#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import random
import re
import shutil
import stat
import subprocess
from collections import defaultdict

RUN = "/home/user/run_pipeline.sh"
PIPELINE = "/home/user/pipeline.py"
INPUT = "/home/user/sensor_data.csv"
OUTPUT = "/home/user/output"


def expected_from_bytes(data):
    text = data.decode("utf-8")
    reader = csv.DictReader(io.StringIO(text, newline=""))
    header = reader.fieldnames
    valid = []
    invalid = []
    for index, row in enumerate(reader):
        try:
            temp = float(row["temperature"])
            hum = float(row["humidity"])
            ok = -20.0 <= temp <= 60.0 and 0.0 <= hum <= 100.0
        except (ValueError, TypeError):
            ok = False
        if ok:
            valid.append((index, row))
        else:
            invalid.append(row)

    valid.sort(key=lambda item: item[1]["timestamp"])
    history = defaultdict(list)
    stats = []
    for _, row in valid:
        sid = row["sensor_id"]
        history[sid].append((float(row["temperature"]), float(row["humidity"])))
        window = history[sid][-3:]
        stats.append({
            "timestamp": row["timestamp"],
            "sensor_id": sid,
            "temp_mavg": round(sum(v[0] for v in window) / len(window), 2),
            "hum_mavg": round(sum(v[1] for v in window) / len(window), 2),
        })
    return header, invalid, stats


def assert_outputs_semantically(input_bytes):
    expected_header, expected_invalid, expected_stats = expected_from_bytes(input_bytes)
    invalid_path = os.path.join(OUTPUT, "invalid_rows.csv")
    stats_path = os.path.join(OUTPUT, "rolling_stats.jsonl")
    assert os.path.isfile(invalid_path), f"Invalid rows file {invalid_path} does not exist."
    assert os.path.isfile(stats_path), f"Rolling stats file {stats_path} does not exist."

    with open(invalid_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        actual_header = reader.fieldnames
        actual_invalid = list(reader)
    assert actual_header == expected_header, f"Header mismatch: {actual_header}"
    assert actual_invalid == expected_invalid, "Contents of invalid_rows.csv do not match expected invalid rows."

    actual_stats = []
    with open(stats_path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                actual_stats.append(json.loads(line))
    assert len(actual_stats) == len(expected_stats), \
        f"Expected {len(expected_stats)} JSON lines, got {len(actual_stats)}."
    for i, (actual, expected) in enumerate(zip(actual_stats, expected_stats), 1):
        assert actual == expected, f"Mismatch at JSON line {i}: expected {expected}, got {actual}."


def assert_json_number_format():
    path = os.path.join(OUTPUT, "rolling_stats.jsonl")
    with open(path, "r", encoding="utf-8", newline="") as f:
        lines = [line.rstrip("\r\n") for line in f if line.strip()]

    def reject_constant(value):
        raise AssertionError(f"Non-finite JSON number {value} is not allowed")

    for number, line in enumerate(lines, 1):
        parsed = json.loads(
            line,
            parse_float=lambda token: ("float", token),
            parse_int=lambda token: ("int", token),
            parse_constant=reject_constant,
        )
        assert set(parsed) == {"timestamp", "sensor_id", "temp_mavg", "hum_mavg"}, \
            f"Wrong keys on JSON line {number}."
        assert isinstance(parsed["timestamp"], str) and isinstance(parsed["sensor_id"], str)
        for key in ("temp_mavg", "hum_mavg"):
            token = parsed[key]
            assert isinstance(token, tuple) and token[0] == "float", \
                f"{key} on line {number} must be a JSON float."
            assert re.fullmatch(r"-?(?:0|[1-9][0-9]*)\.[0-9]{2}", token[1]), \
                f"{key} on line {number} is not formatted with exactly two decimal places: {token[1]}"


def test_complete_pipeline():
    assert os.path.isfile(RUN), f"Orchestrator script {RUN} does not exist."
    assert os.stat(RUN).st_mode & stat.S_IXUSR, f"Script {RUN} is not executable."
    assert os.path.isfile(PIPELINE), f"Python script {PIPELINE} does not exist."

    original_input = open(INPUT, "rb").read()
    original_pipeline = open(PIPELINE, "rb").read()
    original_pipeline_mode = stat.S_IMODE(os.stat(PIPELINE).st_mode)

    try:
        # Execute the submitted orchestrator against the supplied fixture and retain
        # all semantic assertions from the original verifier.
        os.makedirs(OUTPUT, exist_ok=True)
        stale = os.path.join(OUTPUT, "must_be_removed.tmp")
        open(stale, "w").write("stale")
        subprocess.run([RUN], check=True, timeout=20)
        assert os.path.isdir(OUTPUT), "Output directory /home/user/output does not exist."
        assert not os.path.exists(stale), "run_pipeline.sh did not clear the output directory."
        assert open(INPUT, "rb").read() == original_input, "The pipeline modified its input file."
        assert_outputs_semantically(original_input)
        assert_json_number_format()

        # Use a randomized, out-of-order fixture with quoted embedded newlines,
        # tied timestamps, boundary values, malformed values, and deliberately
        # distinctive invalid-record formatting.
        rng = random.SystemRandom()
        year = rng.randrange(2031, 2090)
        base = rng.randrange(8, 25)
        hbase = rng.randrange(20, 61)
        suffix = rng.randrange(100000, 999999)
        s1 = f"sensor_{suffix}A"
        s2 = f"sensor_{suffix}B"
        header = "timestamp,sensor_id,temperature,humidity,notes\n"
        records = [
            (f'{year}-04-03T10:10:00Z,{s1},{base + 2}.10,{hbase + 2}.20,"valid note, with comma"\n', True),
            (f'{year}-04-03T10:05:00Z,{s1},{base}.10,{hbase}.20,"embedded first line\nembedded second line"\n', True),
            (f'{year}-04-03T10:10:00Z,"{s2}",-20.00,100.00,boundary reading\n', True),
            (f'{year}-04-03T10:07:00Z,"{s1}",+060.001,050.000,"invalid spike\nkept verbatim"\n', False),
            (f'{year}-04-03T10:15:00Z,{s1},{base + 4}.10,{hbase + 4}.20,later reading\n', True),
            (f'{year}-04-03T10:12:00Z,{s2},5.25,not-a-number,"bad humidity, unchanged"\n', False),
            (f'{year}-04-03T10:20:00Z,{s1},{base + 6}.10,{hbase + 6}.20,rolling window\n', True),
            (f'{year}-04-03T10:10:00Z,{s1},{base + 3}.10,{hbase + 3}.20,same timestamp stable order\n', True),
        ]
        dynamic_bytes = (header + "".join(record for record, _ in records)).encode("utf-8")
        expected_invalid_bytes = (header + "".join(record for record, valid in records if not valid)).encode("utf-8")
        with open(INPUT, "wb") as f:
            f.write(dynamic_bytes)
        os.makedirs(OUTPUT, exist_ok=True)
        for name in os.listdir(OUTPUT):
            path = os.path.join(OUTPUT, name)
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

        # Execute pipeline.py itself so placeholder Python code cannot be hidden
        # behind an orchestrator that hardcodes the supplied fixture.
        subprocess.run(["python3", PIPELINE], check=True, timeout=20)
        assert_outputs_semantically(dynamic_bytes)
        assert_json_number_format()
        with open(os.path.join(OUTPUT, "invalid_rows.csv"), "rb") as f:
            actual_invalid_bytes = f.read()
        assert actual_invalid_bytes == expected_invalid_bytes, \
            "invalid_rows.csv did not preserve the exact header and original invalid CSV records."

        # Independently prove that the shell script creates/clears output and
        # actually executes /home/user/pipeline.py.
        probe = b'import pathlib\npathlib.Path("/tmp/pipeline_was_executed").write_text("yes")\n'
        with open(PIPELINE, "wb") as f:
            f.write(probe)
        if os.path.exists("/tmp/pipeline_was_executed"):
            os.unlink("/tmp/pipeline_was_executed")
        os.makedirs(OUTPUT, exist_ok=True)
        probe_stale = os.path.join(OUTPUT, "probe_stale_file")
        open(probe_stale, "w").write("remove me")
        subprocess.run([RUN], check=True, timeout=20)
        assert os.path.isdir(OUTPUT), "run_pipeline.sh did not create the output directory."
        assert not os.path.exists(probe_stale), "run_pipeline.sh did not clear existing output files."
        assert os.path.isfile("/tmp/pipeline_was_executed"), \
            "run_pipeline.sh did not execute /home/user/pipeline.py."
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        with open(PIPELINE, "wb") as f:
            f.write(original_pipeline)
        os.chmod(PIPELINE, original_pipeline_mode)
        try:
            subprocess.run([RUN], check=False, timeout=20, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
