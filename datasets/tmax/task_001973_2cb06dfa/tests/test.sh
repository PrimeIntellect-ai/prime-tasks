#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import secrets
import stat
import subprocess

HOME = "/home/user"
PIPELINE = f"{HOME}/pipeline.sh"
SOURCE = f"{HOME}/scorer.c"
WEIGHTS = f"{HOME}/weights.txt"
DATA = f"{HOME}/sensor_data.csv"
SCORED = f"{HOME}/scored_data.csv"
SUMMARY = f"{HOME}/summary.txt"
SCORER = f"{HOME}/scorer"


def expected_data(summary_from_formatted=False):
    weights = {}
    with open(WEIGHTS, encoding="utf-8") as f:
        for line in f:
            key, value = line.strip().split("=", 1)
            weights[key] = float(value)

    rows = []
    scores = {1: [], 2: [], 3: []}
    with open(DATA, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            sid_text = row["sensor_id"].strip()
            if sid_text not in ("1", "2", "3"):
                continue
            sid = int(sid_text)

            pressure_text = row["pressure"].strip()
            if not pressure_text:
                continue
            try:
                pressure = float(pressure_text)
            except ValueError:
                continue

            temperature = 20.0
            temperature_text = row["temperature"].strip()
            if temperature_text and temperature_text.lower() != "nan":
                try:
                    parsed = float(temperature_text)
                    if -50.0 <= parsed <= 150.0:
                        temperature = parsed
                except ValueError:
                    pass

            raw_score = (temperature * weights["w_temp"] +
                         pressure * weights["w_press"] + weights["bias"])
            formatted = f"{raw_score:.2f}"
            rows.append((row["timestamp"], sid_text, formatted))
            scores[sid].append(float(formatted) if summary_from_formatted else raw_score)

    summaries = [(sid, f"{sum(values) / len(values):.2f}")
                 for sid, values in scores.items() if values]
    return rows, summaries


def check_scored(expected_rows):
    assert os.path.exists(SCORED), f"Output file {SCORED} does not exist."
    with open(SCORED, newline="", encoding="utf-8") as f:
        first_line = f.readline().rstrip("\r\n")
        assert first_line == "timestamp,sensor_id,risk_score", \
            "Header in scored_data.csv is incorrect."
        f.seek(0)
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["timestamp", "sensor_id", "risk_score"]
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows, got {len(actual_rows)}."
    for actual, expected in zip(actual_rows, expected_rows):
        assert set(actual) == {"timestamp", "sensor_id", "risk_score"}
        assert actual["timestamp"] == expected[0], "Timestamp mismatch."
        assert actual["sensor_id"] == expected[1], "Sensor ID mismatch."
        assert re.fullmatch(r"-?(?:0|[1-9][0-9]*)\.[0-9]{2}", actual["risk_score"]), \
            f"Risk score is not formatted to exactly two decimals: {actual['risk_score']}"
        assert actual["risk_score"] == expected[2], \
            f"Risk score mismatch for timestamp {actual['timestamp']}: expected {expected[2]}, got {actual['risk_score']}."
        assert math.isclose(float(actual["risk_score"]), float(expected[2]), abs_tol=0.015)


def check_summary(expected_summary):
    assert os.path.exists(SUMMARY), f"Summary file {SUMMARY} does not exist."
    with open(SUMMARY, encoding="utf-8") as f:
        actual_lines = [line.rstrip("\r\n") for line in f]
    expected_lines = [f"{sid}: {value}" for sid, value in expected_summary]
    assert actual_lines == expected_lines, \
        f"summary.txt must contain exactly these numerically sorted lines: {expected_lines}; got {actual_lines}"
    for line in actual_lines:
        assert re.fullmatch(r"[123]: -?(?:0|[1-9][0-9]*)\.[0-9]{2}", line), \
            f"Summary line has incorrect formatting: {line}"


def run_direct_engine(expected_rows, marker_path):
    probe = f"/tmp/scorer_probe_{secrets.token_hex(8)}"
    for path in (SCORED, probe, marker_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    subprocess.run(["gcc", SOURCE, "-o", probe], check=True, timeout=30)
    assert open(probe, "rb").read(4) == b"\x7fELF", "scorer.c did not compile to a native executable."
    subprocess.run([probe], cwd=HOME, check=True, timeout=30)
    assert os.path.exists(marker_path), "The compiled C engine was not executed."
    check_scored(expected_rows)
    os.remove(probe)


def run_pipeline(expected_rows, expected_summary, marker_path, marker_text):
    for path in (SCORED, SUMMARY, SCORER, marker_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    subprocess.run([PIPELINE], cwd=HOME, check=True, timeout=30)
    assert os.path.isfile(SCORER), "pipeline.sh did not create /home/user/scorer."
    st = os.stat(SCORER)
    assert st.st_mode & stat.S_IXUSR, "/home/user/scorer is not executable."
    with open(SCORER, "rb") as f:
        binary = f.read()
    assert binary.startswith(b"\x7fELF"), "/home/user/scorer is not a compiled native executable."
    assert marker_text.encode() in binary, "pipeline.sh did not compile the current /home/user/scorer.c."
    assert os.path.exists(marker_path), "pipeline.sh did not execute the compiled C scorer."
    check_scored(expected_rows)
    check_summary(expected_summary)


def test_complete_reproducible_pipeline():
    assert os.path.exists(PIPELINE), f"Pipeline script {PIPELINE} does not exist."
    assert os.path.isfile(PIPELINE)
    assert os.stat(PIPELINE).st_mode & stat.S_IXUSR, f"Pipeline script {PIPELINE} is not executable."
    with open(PIPELINE, encoding="utf-8", errors="replace") as f:
        first_line = f.readline().strip()
    assert re.match(r"^#!.*\bbash\b", first_line), "pipeline.sh must be a Bash script."
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."

    token = secrets.token_hex(16)
    marker_text = f"VERIFIER_BUILD_{token}"
    marker_path = f"/tmp/verifier_executed_{token}"
    with open(SOURCE, "a", encoding="utf-8") as f:
        f.write("\n#include <stdio.h>\n")
        f.write(f'const char verifier_build_marker_{token}[] = "{marker_text}";\n')
        f.write(f'__attribute__((constructor)) static void verifier_run_marker_{token}(void) '
                '{ FILE *f = fopen("' + marker_path + '", "w"); if (f) { fputs("1", f); fclose(f); } }\n')

    # Preserve and strengthen the original fixture assertions, but only after
    # executing both the submitted C engine and the submitted pipeline.
    original_rows, original_summary = expected_data(summary_from_formatted=False)
    run_direct_engine(original_rows, marker_path)
    run_pipeline(original_rows, original_summary, marker_path, marker_text)

    # Replace the fixture with unpredictable values so precomputed output files
    # or a fixed-fixture implementation cannot pass.
    rng = secrets.SystemRandom()
    w_temp = rng.randint(17, 83) / 100.0
    w_press = rng.randint(91, 147) / 100.0
    bias = -rng.randint(21, 119) / 10.0
    base = rng.randint(7000000000, 8999999000)
    with open(WEIGHTS, "w", encoding="utf-8") as f:
        f.write(f"w_temp={w_temp:.2f}\nw_press={w_press:.2f}\nbias={bias:.1f}\n")
    with open(DATA, "w", encoding="utf-8") as f:
        f.write("timestamp,sensor_id,temperature,pressure\n")
        f.write(f"{base+1},1,25.25,100.4\n")
        f.write(f"{base+2},2,,98.75\n")
        f.write(f"{base+3},3,NaN,103.2\n")
        f.write(f"{base+4},1,151.0,97.1\n")
        f.write(f"{base+5},2,-50.0,99.9\n")
        f.write(f"{base+6},3,150.0,101.1\n")
        f.write(f"{base+7},4,22.0,100.0\n")
        f.write(f"{base+8},A,24.0,100.0\n")
        f.write(f"{base+9},1,23.0,\n")
        f.write(f"{base+10},2,19.0,not-a-number\n")
        f.write(f"{base+11},3,bad-temp,96.3\n")
        f.write(f"{base+12},1,-50.01,102.6\n")

    random_rows, random_summary = expected_data(summary_from_formatted=True)
    run_direct_engine(random_rows, marker_path)
    run_pipeline(random_rows, random_summary, marker_path, marker_text)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
