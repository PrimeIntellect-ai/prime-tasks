#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import pytest
import csv
import secrets
import shutil
import subprocess
import tempfile

PIPELINE = "/home/user/pipeline.sh"
SOURCE = "/home/user/src/clean_join.c"
EXECUTABLE = "/home/user/src/clean_join"
SENSORS = "/home/user/data/sensors.csv"
CALIBRATION = "/home/user/data/calibration.csv"
OUTPUT = "/home/user/output/final_data.csv"


def remove_artifact(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    elif os.path.lexists(path):
        os.unlink(path)


def run_pipeline():
    remove_artifact(EXECUTABLE)
    remove_artifact(OUTPUT)
    result = subprocess.run(
        [PIPELINE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n\nstderr:\n{result.stderr}"
    )


def test_c_code_fixed():
    c_file = "/home/user/src/clean_join.c"
    assert os.path.isfile(c_file), f"C source file {c_file} is missing."

    with open(c_file, "r") as f:
        content = f.read()

    # The bug was using %f to read into double variables. It should be %lf.
    assert "%lf" in content, "The C code does not appear to be fixed. Hint: use '%lf' to read into 'double' variables with fscanf."
    assert "%d,%lf,%lf" in content.replace(" ", ""), "The calibration fscanf format string is not correctly fixed."
    assert "%d,%[^,],%lf" in content.replace(" ", ""), "The sensor fscanf format string is not correctly fixed."


def test_pipeline_script_exists_and_executable():
    script_file = "/home/user/pipeline.sh"
    assert os.path.isfile(script_file), f"Pipeline script {script_file} is missing."

    st = os.stat(script_file)
    assert bool(st.st_mode & stat.S_IXUSR), f"Pipeline script {script_file} is not executable."


def test_final_output_correct():
    sensors_file = "/home/user/data/sensors.csv"
    calibration_file = "/home/user/data/calibration.csv"
    output_file = "/home/user/output/final_data.csv"

    assert os.path.isfile(sensors_file), f"Input file {sensors_file} missing."
    assert os.path.isfile(calibration_file), f"Input file {calibration_file} missing."

    # Execute the submitted pipeline rather than trusting a pre-created output.
    run_pipeline()

    assert os.path.isfile(output_file), f"Output file {output_file} is missing. Did the pipeline run successfully?"

    # Recompute expected output
    calibrations = {}
    with open(calibration_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            parts = line.split(",")
            calibrations[parts[0]] = (float(parts[1]), float(parts[2]))

    expected_rows = []
    with open(sensors_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line: continue
            parts = line.split(",")
            s_id = parts[0]
            timestamp = parts[1]
            val = float(parts[2])

            offset, multiplier = calibrations.get(s_id, (0.0, 1.0))
            cleaned_value = (val + offset) * multiplier
            expected_rows.append((int(s_id), timestamp, f"{cleaned_value:.2f}"))

    # Sort numerically by id (first column)
    expected_rows.sort(key=lambda x: x[0])
    expected_output = [f"{r[0]},{r[1]},{r[2]}" for r in expected_rows]

    # Read actual output
    with open(output_file, "r") as f:
        actual_output = [line.strip() for line in f if line.strip()]

    assert actual_output == expected_output, (
        f"Output data in {output_file} does not match expected sorted output.\n"
        f"Expected:\n{chr(10).join(expected_output)}\n\n"
        f"Actual:\n{chr(10).join(actual_output)}"
    )


def test_source_program_and_pipeline_on_unseen_inputs():
    ids = []
    while len(ids) < 4:
        candidate = 100 + secrets.randbelow(900)
        if candidate not in ids:
            ids.append(candidate)

    calibrations = {}
    calibration_lines = []
    for sensor_id in ids:
        offset = (secrets.randbelow(81) - 40) / 4.0
        multiplier = 1 + secrets.randbelow(3)
        calibrations[sensor_id] = (offset, multiplier)
        calibration_lines.append(f"{sensor_id},{offset},{multiplier}")

    sensor_order = list(reversed(ids))
    sensor_lines = []
    expected_in_stream_order = []
    expected_rows = []
    timestamp_base = 1700000000 + secrets.randbelow(100000)
    for index, sensor_id in enumerate(sensor_order):
        value = (secrets.randbelow(801) - 400) / 4.0
        timestamp = str(timestamp_base + index * 7)
        sensor_lines.append(f"{sensor_id},{timestamp},{value}")
        offset, multiplier = calibrations[sensor_id]
        cleaned = (value + offset) * multiplier
        row = f"{sensor_id},{timestamp},{cleaned:.2f}"
        expected_in_stream_order.append(row)
        expected_rows.append((sensor_id, row))

    sensor_text = "\n".join(sensor_lines) + "\n"
    calibration_text = "\n".join(calibration_lines) + "\n"

    # Independently compile and execute the submitted C source on verifier-created data.
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_exe = os.path.join(temp_dir, "clean_join")
        temp_sensors = os.path.join(temp_dir, "sensors.csv")
        temp_calibration = os.path.join(temp_dir, "calibration.csv")
        with open(temp_sensors, "w") as f:
            f.write(sensor_text)
        with open(temp_calibration, "w") as f:
            f.write(calibration_text)

        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE, "-o", temp_exe],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"Submitted C source did not compile:\n{compile_result.stderr}"

        program_result = subprocess.run(
            [temp_exe, temp_sensors, temp_calibration],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert program_result.returncode == 0, f"Compiled C program failed:\n{program_result.stderr}"
        actual_program_rows = [line.strip() for line in program_result.stdout.splitlines() if line.strip()]
        assert actual_program_rows == expected_in_stream_order, (
            "Compiled C program produced incorrect output on verifier-created inputs.\n"
            f"Expected:\n{chr(10).join(expected_in_stream_order)}\n\n"
            f"Actual:\n{chr(10).join(actual_program_rows)}"
        )

    # Replace the canonical inputs with unseen data and require the pipeline to rebuild and process them.
    with open(SENSORS, "w") as f:
        f.write(sensor_text)
    with open(CALIBRATION, "w") as f:
        f.write(calibration_text)

    run_pipeline()

    assert os.path.isfile(EXECUTABLE), "Pipeline did not create /home/user/src/clean_join."
    executable_stat = os.stat(EXECUTABLE)
    assert executable_stat.st_mode & stat.S_IXUSR, "Pipeline output clean_join is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Pipeline did not produce a compiled native executable."

    assert os.path.isfile(OUTPUT), "Pipeline did not create final_data.csv for verifier-created inputs."
    with open(OUTPUT, "r") as f:
        actual_pipeline_rows = [line.strip() for line in f if line.strip()]
    expected_sorted = [row for _, row in sorted(expected_rows, key=lambda item: item[0])]
    assert actual_pipeline_rows == expected_sorted, (
        "Pipeline produced incorrect output on verifier-created inputs.\n"
        f"Expected:\n{chr(10).join(expected_sorted)}\n\n"
        f"Actual:\n{chr(10).join(actual_pipeline_rows)}"
    )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
