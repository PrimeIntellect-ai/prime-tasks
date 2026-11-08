#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import shutil
import subprocess
import tempfile

import h5py
import numpy as np

SCRIPT = "/home/user/profile_pipeline.sh"
CSV_PATH = "/home/user/profiling_results.csv"
DATA_PATH = "/home/user/data/spectra.h5"
ANALYZER = "/home/user/analyze_mesh.py"
LEVELS = [2, 4, 8, 16]


def read_calls(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def write_exec_wrapper(path, real_path, log_path):
    content = f'''#!/usr/bin/python3
import json
import os
import sys
with open({log_path!r}, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
os.execv({real_path!r}, [{real_path!r}] + sys.argv[1:])
'''
    with open(path, "w") as f:
        f.write(content)
    os.chmod(path, 0o755)


def write_analyzer_wrapper(path, real_path, log_path):
    content = f'''#!/usr/bin/python3
import json
import os
import sys
with open({log_path!r}, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
os.execv(sys.executable, [sys.executable, {real_path!r}] + sys.argv[1:])
'''
    with open(path, "w") as f:
        f.write(content)
    os.chmod(path, 0o755)


def validate_csv(expected_length, expected_peak):
    assert os.path.isfile(CSV_PATH), f"CSV file {CSV_PATH} is missing."
    with open(CSV_PATH, newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) == 5, f"Expected exactly 5 lines in the CSV, found {len(rows)}."
    expected_header = ["Level", "Length", "DensityPeak", "Time", "Rate"]
    assert rows[0] == expected_header, f"Expected header {expected_header}, got {rows[0]}."

    for i, row in enumerate(rows[1:]):
        assert len(row) == 5, f"Row {i+1} does not have exactly 5 columns."
        level = int(row[0])
        length = int(row[1])
        density_peak = float(row[2])
        time_val = float(row[3])
        rate = float(row[4])

        assert level == LEVELS[i], f"Row {i+1} expected level {LEVELS[i]}, got {level}."
        assert length == expected_length, f"Row {i+1} expected length {expected_length}, got {length}."
        expected_density = expected_peak / level
        assert math.isclose(density_peak, expected_density, rel_tol=1e-3), (
            f"Row {i+1} expected DensityPeak ~{expected_density}, got {density_peak}."
        )
        assert time_val > 0, f"Row {i+1} time should be greater than 0."
        # analyze_mesh.py sleeps for 0.05 seconds per level. These broad bounds
        # ensure the recorded value is a plausible real elapsed measurement.
        assert time_val >= 0.04 * level, f"Row {i+1} time {time_val} is implausibly short."
        assert time_val <= 1.0 + 0.25 * level, f"Row {i+1} time {time_val} is implausibly long."
        expected_rate = length / time_val
        assert math.isclose(rate, expected_rate, rel_tol=0.05), (
            f"Row {i+1} expected Rate ~{expected_rate}, got {rate}."
        )


def validate_tool_calls(h5_calls, time_calls, analyzer_calls):
    assert any(DATA_PATH in call for call in h5_calls), (
        "The executed script did not invoke h5dump on the spectroscopy HDF5 file."
    )

    for level in LEVELS:
        level_text = str(level)
        assert any(
            "%e" in call and ANALYZER in call and level_text in call
            for call in time_calls
        ), f"Level {level} was not run through /usr/bin/time using %e."
        assert any(
            len(call) == 2 and call[0] == DATA_PATH and call[1] == level_text
            for call in analyzer_calls
        ), f"The analyzer was not executed with the required arguments for level {level}."


def run_and_check(expected_length, expected_peak, logs):
    starts = {name: len(read_calls(path)) for name, path in logs.items()}
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=40,
    )
    assert result.returncode == 0, (
        f"profile_pipeline.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    validate_csv(expected_length, expected_peak)
    calls = {
        name: read_calls(path)[starts[name]:]
        for name, path in logs.items()
    }
    validate_tool_calls(calls["h5"], calls["time"], calls["analyzer"])


def test_profile_pipeline_end_to_end():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    with open(SCRIPT) as f:
        content = f.read()
    assert "h5dump" in content, "Script does not use 'h5dump' as required."

    work = tempfile.mkdtemp(prefix="profile-verifier-")
    backups = {
        DATA_PATH: os.path.join(work, "spectra.h5"),
        ANALYZER: os.path.join(work, "analyze_mesh.py"),
        "/usr/bin/h5dump": os.path.join(work, "h5dump"),
        "/usr/bin/time": os.path.join(work, "time"),
    }
    logs = {
        "h5": os.path.join(work, "h5.calls"),
        "time": os.path.join(work, "time.calls"),
        "analyzer": os.path.join(work, "analyzer.calls"),
    }

    shutil.copy2(DATA_PATH, backups[DATA_PATH])
    shutil.copy2(ANALYZER, backups[ANALYZER])
    os.replace("/usr/bin/h5dump", backups["/usr/bin/h5dump"])
    os.replace("/usr/bin/time", backups["/usr/bin/time"])

    try:
        write_exec_wrapper("/usr/bin/h5dump", backups["/usr/bin/h5dump"], logs["h5"])
        write_exec_wrapper("/usr/bin/time", backups["/usr/bin/time"], logs["time"])
        write_analyzer_wrapper(ANALYZER, backups[ANALYZER], logs["analyzer"])

        # Preserve and exercise the original verifier's fixed-data assertions.
        run_and_check(5000, 999.9, logs)

        # Replace the input only during verification with an unpredictable shape
        # and peak, then require the script to regenerate the CSV from that input.
        dynamic_length = random.SystemRandom().randint(3201, 4703)
        dynamic_peak = random.SystemRandom().uniform(700.0, 1400.0)
        rng = np.random.default_rng()
        data = rng.uniform(0.0, dynamic_peak / 4.0, dynamic_length)
        data[random.SystemRandom().randrange(dynamic_length)] = dynamic_peak
        with h5py.File(DATA_PATH, "w") as f:
            f.create_dataset("/spectroscopy/signal", data=data)

        run_and_check(dynamic_length, dynamic_peak, logs)
    finally:
        if os.path.exists(backups[DATA_PATH]):
            shutil.copy2(backups[DATA_PATH], DATA_PATH)
        if os.path.exists(backups[ANALYZER]):
            shutil.copy2(backups[ANALYZER], ANALYZER)
        for installed, backup in (
            ("/usr/bin/h5dump", backups["/usr/bin/h5dump"]),
            ("/usr/bin/time", backups["/usr/bin/time"]),
        ):
            if os.path.lexists(installed):
                os.remove(installed)
            if os.path.exists(backup):
                os.replace(backup, installed)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
