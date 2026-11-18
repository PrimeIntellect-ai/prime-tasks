#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import calendar
import json
import os
import subprocess
import tempfile
from datetime import datetime, timezone


def run(cmd, *, cwd=None, input_text=None):
    return subprocess.run(
        cmd,
        cwd=cwd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )


def nonempty_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def test_c_source_exists():
    assert os.path.isfile("/home/user/loc_processor.c"), "The C source file /home/user/loc_processor.c is missing."


def test_makefile_exists():
    assert os.path.isfile("/home/user/Makefile"), "The Makefile /home/user/Makefile is missing."


def test_executable_exists():
    exe_path = "/home/user/loc_processor"
    assert os.path.isfile(exe_path), f"The executable {exe_path} is missing. Did you run 'make all'?"
    assert os.access(exe_path, os.X_OK), f"The file {exe_path} is not executable."


def test_final_stats_tsv_exists_and_content():
    file_path = "/home/user/final_stats.tsv"
    assert os.path.isfile(file_path), f"The file {file_path} is missing. Did you run 'make pipeline'?"

    expected_lines = [
        "1696154400\tfr\tSTR_A\t10\t10.00",
        "1696155300\tfr\tSTR_B\t20\t15.00",
        "1696156200\tde\tSTR_C\t30\t20.00",
        "1696158000\tde\tSTR_D\t15\t21.67"
    ]

    with open(file_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {file_path}, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch in {file_path}.\nExpected: {expected}\nActual:   {actual}"


def test_zz_program_subcommands_and_make_pipeline_on_dynamic_inputs():
    source_binary = "/tmp/loc_processor_from_source"
    compiled = run(["gcc", "/home/user/loc_processor.c", "-o", source_binary, "-lm"])
    assert compiled.returncode == 0, f"loc_processor.c did not compile cleanly:\n{compiled.stdout}\n{compiled.stderr}"
    assert os.path.isfile(source_binary) and os.access(source_binary, os.X_OK)

    with tempfile.TemporaryDirectory() as td:
        base = calendar.timegm((2025, 1, 2, 3, 4, 5, 0, 0, 0))
        csv_path = os.path.join(td, "input.csv")
        json_path = os.path.join(td, "input.json")
        with open(csv_path, "w") as f:
            f.write("Date,ID,Length\n")
            f.write("2025-01-02T03:04:05Z,CSV_ONE,7\n")
            f.write("2025-01-02T03:05:05Z,CSV_TWO,41\n")
        with open(json_path, "w") as f:
            json.dump([
                {"timestamp": base + 20, "key": "JSON_ONE", "chars": 13},
                {"timestamp": base + 90, "key": "JSON_TWO", "chars": 2},
            ], f, indent=2)

        csv_result = run([source_binary, "parse_csv", csv_path, "zz"])
        assert csv_result.returncode == 0, csv_result.stderr
        assert nonempty_lines(csv_result.stdout) == [
            f"{base}\tzz\tCSV_ONE\t7",
            f"{base + 60}\tzz\tCSV_TWO\t41",
        ]

        json_result = run([source_binary, "parse_json", json_path, "yy"])
        assert json_result.returncode == 0, json_result.stderr
        assert nonempty_lines(json_result.stdout) == [
            f"{base + 20}\tyy\tJSON_ONE\t13",
            f"{base + 90}\tyy\tJSON_TWO\t2",
        ]

        rolling_input = (
            "101\taa\tA\t5\n"
            "102\tbb\tB\t8\n"
            "103\tcc\tC\t20\n"
            "104\tdd\tD\t1\n"
            "105\tee\tE\t11\n"
        )
        rolling_result = run([source_binary, "rolling_stats"], input_text=rolling_input)
        assert rolling_result.returncode == 0, rolling_result.stderr
        assert nonempty_lines(rolling_result.stdout) == [
            "101\taa\tA\t5\t5.00",
            "102\tbb\tB\t8\t6.50",
            "103\tcc\tC\t20\t11.00",
            "104\tdd\tD\t1\t9.67",
            "105\tee\tE\t11\t10.67",
        ]

    exe_path = "/home/user/loc_processor"
    os.unlink(exe_path)
    made = run(["make", "all"], cwd="/home/user")
    assert made.returncode == 0, f"make all failed:\n{made.stdout}\n{made.stderr}"
    assert os.path.isfile(exe_path), "make all did not recreate /home/user/loc_processor"
    assert os.access(exe_path, os.X_OK), "make all did not create an executable loc_processor"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "make all did not produce a compiled executable"

    smoke = run([exe_path, "rolling_stats"], input_text="1\tx\tK\t9\n2\tx\tL\t3\n")
    assert smoke.returncode == 0, smoke.stderr
    assert nonempty_lines(smoke.stdout) == [
        "1\tx\tK\t9\t9.00",
        "2\tx\tL\t3\t6.00",
    ]

    csv_fixture = "/home/user/loc_data/en_to_fr.csv"
    json_fixture = "/home/user/loc_data/en_to_de.json"
    with open(csv_fixture, "rb") as f:
        original_csv = f.read()
    with open(json_fixture, "rb") as f:
        original_json = f.read()

    pipeline_base = int(datetime(2024, 2, 3, 4, 5, 6, tzinfo=timezone.utc).timestamp())
    try:
        with open(csv_fixture, "w") as f:
            f.write("Date,ID,Length\n")
            f.write("2024-02-03T04:05:06Z,DYN_A,7\n")
            f.write("2024-02-03T04:05:26Z,DYN_C,41\n")
        with open(json_fixture, "w") as f:
            json.dump([
                {"timestamp": pipeline_base + 10, "key": "DYN_B", "chars": 13},
                {"timestamp": pipeline_base + 30, "key": "DYN_D", "chars": 2},
            ], f, indent=2)

        for path in ["/home/user/fr.tsv", "/home/user/de.tsv", "/home/user/final_stats.tsv"]:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        piped = run(["make", "-B", "pipeline"], cwd="/home/user")
        assert piped.returncode == 0, f"make pipeline failed:\n{piped.stdout}\n{piped.stderr}"
        assert os.path.isfile("/home/user/final_stats.tsv"), "make pipeline did not create final_stats.tsv"
        with open("/home/user/final_stats.tsv") as f:
            actual = nonempty_lines(f.read())
        expected = [
            f"{pipeline_base}\tfr\tDYN_A\t7\t7.00",
            f"{pipeline_base + 10}\tde\tDYN_B\t13\t10.00",
            f"{pipeline_base + 20}\tfr\tDYN_C\t41\t20.33",
            f"{pipeline_base + 30}\tde\tDYN_D\t2\t18.67",
        ]
        assert actual == expected, f"Dynamic pipeline output mismatch.\nExpected: {expected}\nActual: {actual}"
    finally:
        with open(csv_fixture, "wb") as f:
            f.write(original_csv)
        with open(json_fixture, "wb") as f:
            f.write(original_json)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
