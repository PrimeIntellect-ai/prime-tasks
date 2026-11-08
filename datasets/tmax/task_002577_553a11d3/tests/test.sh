#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import ctypes
import json
import os
import secrets
import shutil
import subprocess


def collatz_steps(n):
    steps = 0
    while n != 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        steps += 1
    return steps


def test_shared_library_compiled():
    path = "/home/user/libmath.so"
    assert os.path.isfile(path), f"Shared library {path} is missing. Did you compile it?"


def test_shared_library_is_loadable_and_correct():
    path = "/home/user/libmath.so"
    lib = ctypes.CDLL(path)
    fn = lib.compute_collatz_steps
    fn.argtypes = [ctypes.c_int]
    fn.restype = ctypes.c_int
    for value in [1, 2, 3, 9, 27, 97]:
        assert fn(value) == collatz_steps(value), (
            f"compute_collatz_steps({value}) returned {fn(value)}, "
            f"expected {collatz_steps(value)}"
        )


def test_original_source_still_exists():
    path = "/home/user/math_lib.c"
    assert os.path.isfile(path), f"Original C source {path} was deleted."


def test_orchestrate_script_exists_and_executable():
    path = "/home/user/orchestrate.sh"
    assert os.path.isfile(path), f"Orchestration script {path} is missing."
    assert os.access(path, os.X_OK), f"Orchestration script {path} is not executable."


def test_summary_csv_content():
    path = "/home/user/summary.csv"
    assert os.path.isfile(path), f"Summary CSV {path} is missing."

    expected_rows = [
        ["steps", "file_count"],
        ["7", "1"],
        ["9", "1"],
        ["17", "3"],
        ["19", "2"],
        ["111", "1"],
        ["118", "1"],
        ["178", "1"]
    ]

    actual_rows = []
    with open(path, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert actual_rows == expected_rows, (
        f"CSV content mismatch.\nExpected: {expected_rows}\nActual: {actual_rows}"
    )


def test_organized_data_structure():
    base_dir = "/home/user/organized_data"
    assert os.path.isdir(base_dir), f"Directory {base_dir} is missing."

    expected_structure = {
        "7": ["test_9.json"],
        "9": ["test_5.json"],
        "17": ["test_1.json", "test_6.json", "test_10.json"],
        "19": ["test_3.json", "test_8.json"],
        "111": ["test_2.json"],
        "118": ["test_4.json"],
        "178": ["test_7.json"]
    }

    for steps, files in expected_structure.items():
        step_dir = os.path.join(base_dir, steps)
        assert os.path.isdir(step_dir), f"Directory for {steps} steps ({step_dir}) is missing."

        actual_files = set(os.listdir(step_dir))
        expected_files = set(files)

        assert actual_files == expected_files, (
            f"Mismatch in files for directory {step_dir}.\n"
            f"Expected: {expected_files}\nActual: {actual_files}"
        )


def test_moved_json_contents():
    original = {
        1: 15, 2: 27, 3: 9, 4: 97, 5: 12,
        6: 15, 7: 871, 8: 9, 9: 21, 10: 15,
    }
    for ident, value in original.items():
        steps = collatz_steps(value)
        path = f"/home/user/organized_data/{steps}/test_{ident}.json"
        with open(path) as f:
            actual = json.load(f)
        assert actual == {"id": ident, "value": value}, (
            f"Moved JSON content is wrong for {path}: {actual}"
        )


def test_original_test_data_moved():
    path = "/home/user/test_data"
    if os.path.isdir(path):
        assert len(os.listdir(path)) == 0, f"Original test_data directory {path} is not empty. Files were not moved."


def test_orchestrator_end_to_end_with_ffi():
    home = "/home/user"
    source = os.path.join(home, "math_lib.c")
    orchestrate = os.path.join(home, "orchestrate.sh")
    marker = f"/tmp/ffi_calls_{secrets.token_hex(12)}"
    salt = secrets.randbelow(700) + 200

    ids = set()
    values = set()
    while len(ids) < 6:
        ids.add(secrets.randbelow(800000) + 100000)
    while len(values) < 6:
        values.add(secrets.randbelow(450) + 20)
    records = [
        {"id": ident, "value": value}
        for ident, value in zip(sorted(ids), sorted(values))
    ]

    with open(source, "rb") as f:
        original_source = f.read()

    probe_source = f'''#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
int compute_collatz_steps(int n) {{
    int fd = open("{marker}", O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {{
        char buf[64];
        int len = snprintf(buf, sizeof(buf), "%d\\n", n);
        if (len > 0) write(fd, buf, (size_t)len);
        close(fd);
    }}
    return n * 1000 + {salt};
}}
'''

    try:
        for path in [os.path.join(home, "test_data"), os.path.join(home, "organized_data")]:
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)
        for path in [os.path.join(home, "libmath.so"), os.path.join(home, "summary.csv")]:
            if os.path.lexists(path):
                os.unlink(path)

        os.mkdir(os.path.join(home, "test_data"))
        for record in records:
            path = os.path.join(home, "test_data", f"test_{record['id']}.json")
            with open(path, "w") as f:
                json.dump(record, f)

        with open(source, "w") as f:
            f.write(probe_source)

        result = subprocess.run(
            [orchestrate], cwd=home, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45
        )
        assert result.returncode == 0, (
            f"orchestrate.sh failed with exit code {result.returncode}:\n{result.stdout}"
        )

        library = os.path.join(home, "libmath.so")
        assert os.path.isfile(library), "orchestrate.sh did not compile libmath.so"
        with open(library, "rb") as f:
            assert f.read(4) == b"\x7fELF", "libmath.so is not an ELF shared library"

        assert os.path.isfile(marker), (
            "The instrumented C function was never called; categorization did not use FFI"
        )
        with open(marker) as f:
            calls = [int(line.strip()) for line in f if line.strip()]
        expected_values = {record["value"] for record in records}
        assert expected_values.issubset(set(calls)), (
            f"Not every input was evaluated through the C function. Calls: {calls}"
        )
        assert set(calls).issubset(expected_values), f"Unexpected C function calls: {calls}"

        expected_by_steps = {}
        for record in records:
            steps = record["value"] * 1000 + salt
            expected_by_steps.setdefault(steps, []).append(record)

        organized = os.path.join(home, "organized_data")
        assert os.path.isdir(organized), "organized_data was not created"
        assert set(os.listdir(organized)) == {str(s) for s in expected_by_steps}, (
            "organized_data contains incorrect step directories"
        )

        for steps, expected_records in expected_by_steps.items():
            step_dir = os.path.join(organized, str(steps))
            expected_names = {f"test_{r['id']}.json" for r in expected_records}
            assert set(os.listdir(step_dir)) == expected_names
            for record in expected_records:
                path = os.path.join(step_dir, f"test_{record['id']}.json")
                with open(path) as f:
                    assert json.load(f) == record, f"JSON content changed in {path}"

        remaining = os.path.join(home, "test_data")
        assert os.path.isdir(remaining) and os.listdir(remaining) == [], (
            "Input JSON files were not moved out of test_data"
        )

        expected_csv = [["steps", "file_count"]] + [
            [str(steps), str(len(expected_by_steps[steps]))]
            for steps in sorted(expected_by_steps)
        ]
        with open(os.path.join(home, "summary.csv"), newline="") as f:
            actual_csv = list(csv.reader(f))
        assert actual_csv == expected_csv, (
            f"Dynamic summary mismatch. Expected {expected_csv}, got {actual_csv}"
        )
    finally:
        with open(source, "wb") as f:
            f.write(original_source)
        if os.path.exists(marker):
            os.unlink(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
