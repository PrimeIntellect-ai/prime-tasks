#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import subprocess
import tempfile
import urllib.request

import pytest

C_SOURCE = "/home/user/pipeline/process.c"
BINARY = "/home/user/pipeline/process"
REPORT_PATH = "/home/user/public_html/report.json"
NUMBER = r"-?(?:0|[1-9][0-9]*)\.[0-9]{5}"
OUTPUT_PATTERN = re.compile(
    rf'\A\s*\{{\s*"sensor"\s*:\s*"S-100"\s*,\s*'
    rf'"latest_zscores"\s*:\s*\[\s*({NUMBER})\s*,\s*({NUMBER})\s*,\s*'
    rf'({NUMBER})\s*,\s*({NUMBER})\s*,\s*({NUMBER})\s*\]\s*,\s*'
    rf'"reference_distance"\s*:\s*({NUMBER})\s*\}}\s*\Z'
)
REF = [0.1, -0.2, 0.5, 1.0, -1.0]


def expected_for(vals):
    mean = sum(vals) / 5.0
    var = sum((v - mean) ** 2 for v in vals) / 5.0
    std = math.sqrt(var)
    zscores = [(v - mean) / std if std != 0 else 0.0 for v in vals]
    distance = math.sqrt(sum((zscores[i] - REF[i]) ** 2 for i in range(5)))
    return zscores, distance


def assert_output(output, vals):
    match = OUTPUT_PATTERN.fullmatch(output)
    assert match, "Program output must contain exactly the required JSON fields, with every float printed using exactly five decimal places."

    try:
        report = json.loads(output)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Program output is not valid JSON: {exc}")

    assert report["sensor"] == "S-100"
    assert len(report["latest_zscores"]) == 5
    expected_z, expected_dist = expected_for(vals)
    for i, (actual, expected) in enumerate(zip(report["latest_zscores"], expected_z)):
        assert math.isclose(actual, expected, abs_tol=1e-4), \
            f"Z-score at index {i} mismatch. Expected {expected:.5f}, got {actual}"
    assert math.isclose(report["reference_distance"], expected_dist, abs_tol=1e-4), \
        f"Reference distance mismatch. Expected {expected_dist:.5f}, got {report['reference_distance']}"


def csv_record(timestamp, sensor, value, notes):
    quoted_notes = '"' + notes.replace('"', '""') + '"'
    return f"{timestamp},{sensor},{value},{quoted_notes}\n"


def make_case(target_values):
    chunks = ["timestamp,sensor_id,value,notes\n"]
    for i, value in enumerate(target_values):
        notes = f"target note {i}"
        if i == 1:
            notes = "embedded, comma"
        elif i == 3:
            notes = "embedded\nnewline, and comma"
        elif i == 5:
            notes = "several\nphysical\nlines"
        chunks.append(csv_record(f"2026-01-01T00:{i:02d}:00Z", "S-100", f"{value:.8f}", notes))
        if i in (0, 2, 4, 6):
            chunks.append(csv_record(f"2026-01-02T00:{i:02d}:00Z", "S-100X", "999999.25", "must not match\nS-100"))
            chunks.append(csv_record(f"2026-01-03T00:{i:02d}:00Z", "S-200", "-888888.5", "ignored, row"))
    return "".join(chunks)


def run_program(path, csv_text):
    result = subprocess.run(
        [path], input=csv_text, text=True, capture_output=True, timeout=5, check=False
    )
    assert result.returncode == 0, f"{path} exited with {result.returncode}: {result.stderr}"
    assert result.stderr == "", f"{path} unexpectedly wrote to stderr: {result.stderr}"
    return result.stdout


@pytest.fixture(scope="session")
def rebuilt_binary():
    fd, path = tempfile.mkstemp(prefix="process-rebuilt-")
    os.close(fd)
    os.unlink(path)
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_SOURCE, "-lm", "-o", path],
        text=True, capture_output=True, timeout=15, check=False,
    )
    assert result.returncode == 0, f"process.c does not compile successfully:\n{result.stdout}\n{result.stderr}"
    yield path
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def test_c_program_exists():
    assert os.path.isfile(C_SOURCE), f"C source file {C_SOURCE} is missing. You must write your code here."
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing. Did you compile your C program?"
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The compiled process artifact must be an ELF executable."


def test_program_parses_dynamic_csv_and_rebuilt_source(rebuilt_binary):
    rng = random.SystemRandom()
    prefix = [rng.randint(-5000, 5000) / 13.0 for _ in range(3)]
    final = [rng.randint(-9000, 9000) / 17.0 for _ in range(5)]
    while max(final) == min(final):
        final = [rng.randint(-9000, 9000) / 17.0 for _ in range(5)]

    cases = [
        (make_case(prefix + final), final),
        (make_case([rng.randint(-100, 100) / 3.0] + [37.25] * 5), [37.25] * 5),
    ]
    for executable in (BINARY, rebuilt_binary):
        for csv_text, expected_window in cases:
            assert_output(run_program(executable, csv_text), expected_window)


def test_report_json_file_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing. Did you save the output?"


def test_saved_report_is_process_output():
    with open("/home/user/data/sensor_readings.csv", "r", encoding="utf-8") as f:
        csv_text = f.read()
    generated = run_program(BINARY, csv_text)
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        saved = f.read()
    assert saved == generated, "report.json must be the output produced by process for sensor_readings.csv."


def test_web_server_and_report_content():
    url = "http://localhost:8080/report.json"
    try:
        response = urllib.request.urlopen(url, timeout=5)
        data = response.read().decode("utf-8")
    except Exception as e:
        pytest.fail(f"Failed to fetch {url}. Is the web server running on port 8080? Error: {e}")

    try:
        report = json.loads(data)
    except json.JSONDecodeError:
        pytest.fail("The served report.json is not valid JSON.")

    assert "sensor" in report, "Missing 'sensor' key in JSON."
    assert report["sensor"] == "S-100", f"Expected sensor 'S-100', got {report['sensor']}"
    assert "latest_zscores" in report, "Missing 'latest_zscores' key in JSON."
    assert "reference_distance" in report, "Missing 'reference_distance' key in JSON."

    vals = [15.0, 14.0, 16.0, 15.0, 18.0]
    expected_z, expected_dist = expected_for(vals)
    zscores = report["latest_zscores"]
    assert len(zscores) == 5, f"Expected 5 Z-scores, got {len(zscores)}"
    for i, (actual, expected) in enumerate(zip(zscores, expected_z)):
        assert math.isclose(actual, expected, abs_tol=1e-4), \
            f"Z-score at index {i} mismatch. Expected {expected:.5f}, got {actual}"
    actual_dist = report["reference_distance"]
    assert math.isclose(actual_dist, expected_dist, abs_tol=1e-4), \
        f"Reference distance mismatch. Expected {expected_dist:.5f}, got {actual_dist}"

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        assert data == f.read(), "The server on port 8080 is not serving the required report.json file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
