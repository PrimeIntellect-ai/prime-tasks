#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

CPP_FILE = "/home/user/compute_shift.cpp"
SH_FILE = "/home/user/run_pipeline.sh"
BIN_FILE = "/home/user/compute_shift"
REPORT_FILE = "/home/user/shift_report.txt"
TRAIN_FILE = "/home/user/train_data.txt"
VAL_FILE = "/home/user/val_data.txt"


def run(cmd, timeout=30):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout)


def expected_output(train, val):
    xs = sorted(set(train + val))
    distance = max(
        abs(sum(v <= x for v in train) / len(train) -
            sum(v <= x for v in val) / len(val))
        for x in xs
    )
    decision = "REJECT" if distance > 0.05 else "ACCEPT"
    return f"{distance:.4f}\n{decision}\n"


def assert_exact_output(actual, train, val):
    expected = expected_output(train, val)
    assert actual == expected, f"Expected {expected!r}, got {actual!r}"


def test_compute_shift_cpp_exists():
    """Verify that the C++ source file exists."""
    assert os.path.isfile(CPP_FILE), f"Expected C++ file {CPP_FILE} does not exist."


def test_run_pipeline_sh_exists_and_executable():
    """Verify that the bash script exists and is executable."""
    assert os.path.isfile(SH_FILE), f"Expected bash script {SH_FILE} does not exist."
    assert os.access(SH_FILE, os.X_OK), f"Bash script {SH_FILE} is not executable."


def test_pipeline_generates_original_report():
    """Run the submitted pipeline and retain the original report assertions."""
    result = run([SH_FILE], timeout=60)
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(REPORT_FILE), f"Expected report file {REPORT_FILE} does not exist."

    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {REPORT_FILE}, found {len(lines)}."
    ks_stat_str = lines[0]
    decision = lines[1]

    try:
        float(ks_stat_str)
    except ValueError:
        pytest.fail(f"First line of {REPORT_FILE} is not a valid float: {ks_stat_str}")

    assert ks_stat_str in ["0.0592", "0.0593"], \
        f"Expected KS distance to be 0.0592 or 0.0593, got {ks_stat_str}"
    assert decision == "REJECT", f"Expected decision to be REJECT, got {decision}"


def test_cpp_is_compilable_and_computes_ks_on_derived_cases():
    with tempfile.TemporaryDirectory() as td:
        exe = os.path.join(td, "compute_shift_test")
        compiled = run(["g++", "-O3", "-std=c++17", CPP_FILE, "-o", exe], timeout=60)
        assert compiled.returncode == 0, compiled.stderr

        rng = random.SystemRandom()
        cases = [
            ([0.0, 0.0, 1.0, 1.0], [0.0, 0.0, 1.0, 1.0]),
            ([0.0, 1.0], [10.0, 11.0]),
            ([float(i) for i in range(20)], [i + 0.5 for i in range(20)]),
            ([rng.uniform(-4, 4) for _ in range(47)],
             [rng.uniform(-3, 5) for _ in range(53)]),
        ]

        for index, (train, val) in enumerate(cases):
            train_path = os.path.join(td, f"train_{index}.txt")
            val_path = os.path.join(td, f"val_{index}.txt")
            with open(train_path, "w") as f:
                f.writelines(f"{x:.17g}\n" for x in train)
            with open(val_path, "w") as f:
                f.writelines(f"{x:.17g}\n" for x in val)

            result = run([exe, train_path, val_path])
            assert result.returncode == 0, result.stderr
            assert_exact_output(result.stdout, train, val)

        for bad_args in ([], [cases and train_path], [train_path, val_path, train_path]):
            result = run([exe] + bad_args)
            assert result.returncode != 0, \
                f"Program must reject argument count {len(bad_args)}"


def test_wrapper_compiles_and_executes_the_requested_source_and_paths():
    original_source = open(CPP_FILE, "rb").read()
    original_train = open(TRAIN_FILE, "rb").read()
    original_val = open(VAL_FILE, "rb").read()
    token = f"0.{secrets.randbelow(8999) + 1000:04d}"

    probe = f'''#include <fstream>\n#include <iostream>\n#include <string>\nint main(int argc, char** argv) {{\n    if (argc != 3) return 21;\n    if (std::string(argv[1]) != "{TRAIN_FILE}") return 22;\n    if (std::string(argv[2]) != "{VAL_FILE}") return 23;\n    std::ifstream a(argv[1]), b(argv[2]);\n    double x, y;\n    if (!(a >> x) || !(b >> y)) return 24;\n    std::cout << "{token}\\nREJECT\\n";\n    return 0;\n}}\n'''

    try:
        with open(CPP_FILE, "w") as f:
            f.write(probe)
        for path in (BIN_FILE, REPORT_FILE):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        result = run([SH_FILE], timeout=60)
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(BIN_FILE) and os.access(BIN_FILE, os.X_OK), \
            "Pipeline did not create the requested executable"
        assert os.path.isfile(REPORT_FILE), "Pipeline did not create shift_report.txt"
        with open(REPORT_FILE, "r") as f:
            assert f.read() == f"{token}\nREJECT\n", \
                "Pipeline did not compile and execute compute_shift.cpp with the required paths"
    finally:
        with open(CPP_FILE, "wb") as f:
            f.write(original_source)
        with open(TRAIN_FILE, "wb") as f:
            f.write(original_train)
        with open(VAL_FILE, "wb") as f:
            f.write(original_val)
        restored = run([SH_FILE], timeout=60)
        assert restored.returncode == 0, restored.stderr
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
