#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import pytest

C_FILE = "/home/user/preprocess.c"
TUNE_FILE = "/home/user/tune.sh"
DATA_FILE = "/home/user/raw_data.csv"
BEST_FILE = "/home/user/best_t.txt"
EXE_FILE = "/tmp/preprocess_test_exe"


def compile_submission():
    compile_proc = subprocess.run(
        ["gcc", C_FILE, "-o", EXE_FILE], capture_output=True, text=True
    )
    assert compile_proc.returncode == 0, (
        f"Failed to compile {C_FILE}:\n{compile_proc.stderr}"
    )


def parse_only_number(output):
    text = output.strip()
    assert re.fullmatch(
        r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", text
    ), f"Expected only one numeric mean on stdout, but got: {output!r}"
    return float(text)


def expected_mean(rows, threshold):
    values = []
    for _, val1, val2 in rows:
        if val1 == -999:
            val1 = 0
        if val2 == -999:
            val2 = 0
        val3 = val1 * val1 + val2
        if val3 > threshold:
            val3 = threshold
        values.append(val3)
    return sum(values) / len(values)


def test_preprocess_c_exists():
    file_path = C_FILE
    assert os.path.exists(file_path), f"The C program {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} should be a file."


def test_tune_sh_exists():
    file_path = TUNE_FILE
    assert os.path.exists(file_path), f"The bash script {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} should be a file."


def test_best_t_txt_content():
    file_path = BEST_FILE
    assert os.path.exists(file_path), (
        f"The output file {file_path} is missing. Did the bash script run?"
    )
    with open(file_path, "r") as f:
        content = f.read().strip()
    assert content == "150", (
        f"Expected /home/user/best_t.txt to contain '150', but found '{content}'."
    )


def test_preprocess_c_logic():
    compile_submission()

    run_proc = subprocess.run(
        [EXE_FILE, DATA_FILE, "100"], capture_output=True, text=True
    )
    assert run_proc.returncode == 0, (
        f"Running the compiled C program failed:\n{run_proc.stderr}"
    )
    mean_val = parse_only_number(run_proc.stdout)
    assert abs(mean_val - 45.5) < 0.01, (
        f"Expected mean for T=100 to be 45.5, but got {mean_val}"
    )

    run_proc2 = subprocess.run(
        [EXE_FILE, DATA_FILE, "150"], capture_output=True, text=True
    )
    assert run_proc2.returncode == 0, (
        f"Running the compiled C program failed:\n{run_proc2.stderr}"
    )
    mean_val2 = parse_only_number(run_proc2.stdout)
    assert abs(mean_val2 - 58.0) < 0.01, (
        f"Expected mean for T=150 to be 58.0, but got {mean_val2}"
    )


def test_preprocess_on_derived_unseen_inputs():
    compile_submission()
    rng = random.Random(948217)

    for case_index in range(4):
        rows = []
        for row_id in range(1, 12 + case_index):
            val1 = rng.choice([-999, -8, -3, 0, 2, 4, 7, 11, 16, 23])
            val2 = rng.choice([-999, -25, -4, 0, 3, 9, 18, 41, 76])
            rows.append((row_id, val1, val2))
        threshold = rng.choice([17, 37, 83, 127, 211, 319])

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".csv", delete=False
        ) as data:
            data.write("id,val1,val2\n")
            for row in rows:
                data.write(f"{row[0]},{row[1]},{row[2]}\n")
            path = data.name

        try:
            proc = subprocess.run(
                [EXE_FILE, path, str(threshold)],
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert proc.returncode == 0, proc.stderr
            actual = parse_only_number(proc.stdout)
            expected = expected_mean(rows, threshold)
            assert abs(actual - expected) < 0.01, (
                f"For generated CSV case {case_index} and T={threshold}, "
                f"expected {expected}, got {actual}"
            )
        finally:
            os.unlink(path)


def test_preprocess_requires_exactly_two_arguments():
    compile_submission()
    for args in ([], [DATA_FILE], [DATA_FILE, "100", "extra"]):
        proc = subprocess.run(
            [EXE_FILE] + args, capture_output=True, text=True, timeout=5
        )
        assert proc.returncode != 0, (
            f"Program should reject argument list {args!r}, but exited successfully"
        )


def test_tune_script_is_executed_and_performs_the_sweep():
    with open(C_FILE, "rb") as f:
        original_source = f.read()

    call_log = "/tmp/tune_threshold_calls.txt"
    instrumented_source = r'''#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    FILE *log = fopen("/tmp/tune_threshold_calls.txt", "a");
    if (!log) return 3;
    fprintf(log, "%s\n", argv[2]);
    fclose(log);
    int t = atoi(argv[2]);
    printf("%.2f\n", t >= 50 ? 51.0 : 49.0);
    return 0;
}
'''

    try:
        if os.path.exists(BEST_FILE):
            os.unlink(BEST_FILE)
        real_run = subprocess.run(
            ["bash", TUNE_FILE],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert real_run.returncode == 0, (
            f"tune.sh failed on the supplied data:\n{real_run.stdout}\n{real_run.stderr}"
        )
        assert os.path.isfile(BEST_FILE), "tune.sh did not create best_t.txt"
        with open(BEST_FILE) as f:
            assert f.read().strip() == "150"

        with open(C_FILE, "w") as f:
            f.write(instrumented_source)
        if os.path.exists(call_log):
            os.unlink(call_log)
        if os.path.exists(BEST_FILE):
            os.unlink(BEST_FILE)

        sweep_run = subprocess.run(
            ["bash", TUNE_FILE],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert sweep_run.returncode == 0, (
            f"tune.sh failed while its compilation and sweep were exercised:\n"
            f"{sweep_run.stdout}\n{sweep_run.stderr}"
        )
        assert os.path.isfile(BEST_FILE), "tune.sh did not recreate best_t.txt"
        with open(BEST_FILE) as f:
            chosen = f.read().strip()
        assert chosen == "50", (
            f"Expected the smallest threshold producing a mean > 50 to be 50, "
            f"but tune.sh wrote {chosen!r}"
        )
        assert os.path.isfile(call_log), (
            "The executable compiled from preprocess.c was not run by tune.sh"
        )
        with open(call_log) as f:
            calls = [line.strip() for line in f if line.strip()]
        assert set(calls) == {"10", "50", "100", "150", "200"}, (
            f"tune.sh must run the compiled program for every required threshold; "
            f"observed calls were {calls!r}"
        )
    finally:
        with open(C_FILE, "wb") as f:
            f.write(original_source)
        subprocess.run(
            ["bash", TUNE_FILE],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=20,
        )
        if os.path.exists(call_log):
            os.unlink(call_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
