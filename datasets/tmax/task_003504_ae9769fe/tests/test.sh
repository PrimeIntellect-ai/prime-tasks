#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess

PROCESS_PATH = "/home/user/process.go"
RAW_PATH = "/home/user/raw.csv"
CLEAN_PATH = "/home/user/clean.csv"
BINARY_PATH = "/tmp/submission_process"

ORIGINAL_RAW = '''Time,Station,Data
1,Alpha,"Temp: 20.0
Hum: 50.0"
2,Alpha,"Hum: 52.0"
3,Alpha,"Temp: 24.0
Hum: 51.0"
1,Beta,"Temp: 15.0"
2,Beta,"Temp: 16.0
Hum: 60.0"
'''

ORIGINAL_EXPECTED = '''Time,Station,Metric,Value,RollAvg
1,Alpha,Hum,50.0,50.0
2,Alpha,Hum,52.0,51.0
3,Alpha,Hum,51.0,51.5
1,Alpha,Temp,20.0,20.0
2,Alpha,Temp,20.0,20.0
3,Alpha,Temp,24.0,22.0
1,Beta,Hum,0.0,0.0
2,Beta,Hum,60.0,30.0
1,Beta,Temp,15.0,15.0
2,Beta,Temp,16.0,15.5'''


def assert_exact_output(expected_content):
    assert os.path.isfile(CLEAN_PATH), (
        f"File {CLEAN_PATH} does not exist. The Go program may not have run "
        "or output to the wrong path."
    )
    with open(CLEAN_PATH, "r", newline="") as f:
        content = f.read().strip()

    expected_lines = expected_content.splitlines()
    actual_lines = content.splitlines()
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {CLEAN_PATH}, "
        f"but found {len(actual_lines)}."
    )
    for i, (expected_line, actual_line) in enumerate(zip(expected_lines, actual_lines)):
        assert actual_line == expected_line, (
            f"Line {i + 1} mismatch: expected '{expected_line}', got '{actual_line}'"
        )


def run_submission():
    if os.path.lexists(CLEAN_PATH):
        os.remove(CLEAN_PATH)
    result = subprocess.run(
        [BINARY_PATH], cwd="/home/user", capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"Go program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def make_dynamic_fixture():
    suffix = secrets.token_hex(5)
    stations = [f"North_{suffix}", f"South_{suffix}"]
    base = secrets.randbelow(20) * 2 + 10

    records = [
        (3, stations[1], {"Temp": base + 18}),
        (1, stations[0], {"Temp": base}),
        (4, stations[0], {"Temp": base + 8, "Hum": base + 30}),
        (2, stations[1], {"Temp": base + 14, "Hum": base + 40}),
        (2, stations[0], {"Hum": base + 24}),
        (1, stations[1], {"Hum": base + 36}),
        (4, stations[1], {"Hum": base + 44}),
        (3, stations[0], {}),
    ]

    with open(RAW_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["Time", "Station", "Data"])
        for time_value, station, values in records:
            data = "\n".join(f"{metric}: {value:.1f}" for metric, value in values.items())
            writer.writerow([time_value, station, data])

    by_station = {station: [] for station in stations}
    for time_value, station, values in records:
        by_station[station].append((time_value, values))

    lines = ["Time,Station,Metric,Value,RollAvg"]
    for station in sorted(stations):
        ordered = sorted(by_station[station], key=lambda row: row[0])
        for metric in ("Hum", "Temp"):
            previous_value = 0.0
            previous_imputed = None
            for time_value, values in ordered:
                if metric in values:
                    current = float(values[metric])
                    previous_value = current
                else:
                    current = previous_value
                roll_avg = current if previous_imputed is None else (previous_imputed + current) / 2.0
                lines.append(
                    f"{time_value},{station},{metric},{current:.1f},{roll_avg:.1f}"
                )
                previous_imputed = current
    return "\n".join(lines)


def test_go_program_and_output():
    assert os.path.exists(PROCESS_PATH), f"Required Go source {PROCESS_PATH} does not exist."
    mode = os.lstat(PROCESS_PATH).st_mode
    assert stat.S_ISREG(mode), f"{PROCESS_PATH} must be a regular file."
    assert os.path.getsize(PROCESS_PATH) > 0, f"{PROCESS_PATH} is empty."

    build = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, PROCESS_PATH],
        cwd="/home/user", capture_output=True, text=True, timeout=60
    )
    assert build.returncode == 0, (
        f"Failed to build {PROCESS_PATH}.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    # Preserve the original exact-content assertion, but generate the file by
    # executing the submitted program rather than trusting a prewritten CSV.
    with open(RAW_PATH, "w", newline="") as f:
        f.write(ORIGINAL_RAW)
    run_submission()
    assert_exact_output(ORIGINAL_EXPECTED)

    # Exercise parsing, sorting, both imputation cases, and rolling averages on
    # an unpredictable multiline-CSV fixture whose expected result is derived here.
    dynamic_expected = make_dynamic_fixture()
    run_submission()
    assert_exact_output(dynamic_expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
