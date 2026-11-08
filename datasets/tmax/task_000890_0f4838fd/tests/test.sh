#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
import pytest

PIPELINE_DIR = "/home/user/etl_pipeline"
RAW_DIR = os.path.join(PIPELINE_DIR, "raw")
MASKED_DIR = os.path.join(PIPELINE_DIR, "masked")
AGGREGATE_FILE = os.path.join(PIPELINE_DIR, "aggregate.csv")
MASKER_C = os.path.join(PIPELINE_DIR, "masker.c")
MASKER_EXEC = os.path.join(PIPELINE_DIR, "masker")
MAKEFILE = os.path.join(PIPELINE_DIR, "Makefile")

RAW_FILES = {
    "raw_data1.csv": [
        "2023-10-01T10:00:00,SENSOR_A,USER_123,22.5",
        "2023-10-01T10:01:00,SENSOR_B,USER_456,23.1",
        "2023-10-01T10:02:00,SENSOR_A,USER_123,22.7"
    ],
    "raw_data2.csv": [
        "2023-10-01T10:03:00,SENSOR_C,USER_789,19.8",
        "2023-10-01T10:04:00,SENSOR_A,USER_001,21.0"
    ],
    "raw_data3.csv": [
        "2023-10-01T10:05:00,SENSOR_B,USER_456,23.5",
        "2023-10-01T10:06:00,SENSOR_C,USER_999,19.2"
    ]
}

def djb2(s):
    h = 5381
    for c in s:
        h = ((h << 5) + h + ord(c)) & 0xFFFFFFFF
    return f"{h:08x}"

def get_expected_masked_content(raw_lines):
    masked_lines = []
    for line in raw_lines:
        parts = line.strip().split(',')
        if len(parts) >= 3:
            parts[2] = djb2(parts[2])
        masked_lines.append(",".join(parts))
    return masked_lines

def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)

def clean_products():
    remove_path(MASKER_EXEC)
    remove_path(MASKED_DIR)
    remove_path(AGGREGATE_FILE)

def run_make():
    result = subprocess.run(
        ["make", "-j4", "all"], cwd=PIPELINE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=30
    )
    assert result.returncode == 0, "make -j4 all failed:\n" + result.stdout

def expected_bytes(lines):
    return ("\n".join(get_expected_masked_content(lines)) + "\n").encode("ascii")

@pytest.fixture(scope="session", autouse=True)
def exercise_fresh_build_and_runtime_inputs():
    assert os.path.exists(MASKER_C), f"Source file {MASKER_C} is missing."
    assert os.path.exists(MAKEFILE), f"Makefile {MAKEFILE} is missing."

    dry = subprocess.run(
        ["make", "-Bn", "masker"], cwd=PIPELINE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=15
    )
    assert dry.returncode == 0, "Makefile cannot build masker:\n" + dry.stdout
    assert "gcc" in dry.stdout and "-O3" in dry.stdout and "masker.c" in dry.stdout, \
        "The masker target must compile masker.c using gcc -O3."

    raw_paths = {name: os.path.join(RAW_DIR, name) for name in RAW_FILES}
    backups = {name: open(path, "rb").read() for name, path in raw_paths.items()}
    token = secrets.token_hex(12)
    runtime_raw = {
        "raw_data1.csv": [
            f"2041-07-03T01:02:03,SENSOR_{token},RUNTIME_USER_{token},-17.250",
            f"2041-07-03T01:02:04,SENSOR-Z,another_{token},0"
        ],
        "raw_data2.csv": [
            f"1999-12-31T23:59:59,device.with.dots,{token}_MixedCase,00042.00"
        ],
        "raw_data3.csv": [
            f"2100-01-01T00:00:00,SENSOR_LAST,user-{token}-xyz,9.876543",
            f"2100-01-01T00:00:01,SENSOR_REPEAT,RUNTIME_USER_{token},unchanged-value"
        ]
    }

    try:
        for name, lines in runtime_raw.items():
            with open(raw_paths[name], "wb") as f:
                f.write(("\n".join(lines) + "\n").encode("ascii"))

        clean_products()
        run_make()

        assert os.path.isfile(MASKER_EXEC), "make did not create the masker executable."
        assert stat.S_ISREG(os.lstat(MASKER_EXEC).st_mode), "masker is not a regular file."
        assert os.access(MASKER_EXEC, os.X_OK), "masker is not executable."
        with open(MASKER_EXEC, "rb") as f:
            assert f.read(4) == b"\x7fELF", "masker is not a compiled executable."

        assert os.path.isdir(MASKED_DIR) and not os.path.islink(MASKED_DIR), \
            "make did not create a real masked directory."
        for name, lines in runtime_raw.items():
            output_path = os.path.join(MASKED_DIR, name)
            assert os.path.isfile(output_path), f"make did not create {output_path}."
            with open(output_path, "rb") as f:
                assert f.read() == expected_bytes(lines), f"Incorrect runtime output in {output_path}."

        aggregate_expected = b"".join(
            expected_bytes(runtime_raw[name])
            for name in ["raw_data1.csv", "raw_data2.csv", "raw_data3.csv"]
        )
        with open(AGGREGATE_FILE, "rb") as f:
            assert f.read() == aggregate_expected, \
                "aggregate.csv was not generated from the three runtime inputs in order."

        direct_token = secrets.token_hex(16)
        long_sensor = "S" * 850
        direct_lines = [
            f"2037-04-05T06:07:08,{long_sensor},direct_{direct_token},VALUE-UNCHANGED",
            f"2037-04-05T06:07:09,SENSOR_X,second_{direct_token},-0.0001"
        ]
        direct_input = ("\n".join(direct_lines) + "\n").encode("ascii")
        direct = subprocess.run(
            [MASKER_EXEC], input=direct_input,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        assert direct.returncode == 0, f"masker failed on additional input: {direct.stderr!r}"
        assert direct.stdout == expected_bytes(direct_lines), \
            "masker does not correctly transform additional runtime-generated input."
    finally:
        for name, data in backups.items():
            with open(raw_paths[name], "wb") as f:
                f.write(data)
        clean_products()
        run_make()

    yield

def test_source_files_exist():
    assert os.path.exists(MASKER_C), f"Source file {MASKER_C} is missing."
    assert os.path.exists(MAKEFILE), f"Makefile {MAKEFILE} is missing."

def test_executable_exists():
    assert os.path.exists(MASKER_EXEC), f"Executable {MASKER_EXEC} is missing. Was it compiled?"
    assert os.access(MASKER_EXEC, os.X_OK), f"File {MASKER_EXEC} is not executable."

def test_masked_directory_exists():
    assert os.path.exists(MASKED_DIR), f"Directory {MASKED_DIR} is missing."
    assert os.path.isdir(MASKED_DIR), f"Path {MASKED_DIR} is not a directory."

@pytest.mark.parametrize("filename, raw_lines", RAW_FILES.items())
def test_masked_files(filename, raw_lines):
    masked_filepath = os.path.join(MASKED_DIR, filename)
    assert os.path.exists(masked_filepath), f"Masked file {masked_filepath} is missing."

    with open(masked_filepath, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = get_expected_masked_content(raw_lines)
    assert actual_lines == expected_lines, f"Content mismatch in {masked_filepath}."

def test_aggregate_file():
    assert os.path.exists(AGGREGATE_FILE), f"Aggregate file {AGGREGATE_FILE} is missing."

    with open(AGGREGATE_FILE, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = []
    for filename in ["raw_data1.csv", "raw_data2.csv", "raw_data3.csv"]:
        expected_lines.extend(get_expected_masked_content(RAW_FILES[filename]))

    assert actual_lines == expected_lines, f"Content mismatch in {AGGREGATE_FILE}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
