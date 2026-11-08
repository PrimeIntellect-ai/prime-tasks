#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest


def test_mre_csv_content():
    path = "/home/user/mre.csv"
    assert os.path.isfile(path), f"MRE file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "-17,Malicious_User,999"
    assert content == expected, f"Expected {path} to contain exactly '{expected}', but got '{content}'."


def test_ticket_resolution_content():
    path = "/home/user/ticket_resolution.txt"
    assert os.path.isfile(path), f"Resolution report {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {path}, but found {len(lines)}."
    assert lines[0] == "-17", f"Expected line 1 to be '-17', but got '{lines[0]}'."
    assert lines[1] == "734", f"Expected line 2 to be '734', but got '{lines[1]}'."


def test_csv_transformer_fixed_and_compiles():
    source_path = "/home/user/csv_transformer.c"
    binary_path = "/home/user/csv_transformer_test_bin"
    data_path = "/home/user/data/customer_records.csv"

    assert os.path.isfile(source_path), f"Source file {source_path} does not exist."
    assert os.path.isfile(data_path), f"Data file {data_path} does not exist."

    # Recompile the source code to ensure the fix is actually in the C file
    compile_proc = subprocess.run(
        ["gcc", "-g", "-o", binary_path, source_path],
        capture_output=True,
        text=True
    )
    assert compile_proc.returncode == 0, f"Compilation of {source_path} failed:\n{compile_proc.stderr}"

    # Run the compiled binary against the data file
    run_proc = subprocess.run(
        [binary_path, data_path],
        capture_output=True,
        text=True
    )

    # Clean up the test binary
    if os.path.exists(binary_path):
        os.remove(binary_path)

    assert run_proc.returncode == 0, (
        f"Running the patched program failed with exit code {run_proc.returncode}.\n"
        f"Stderr: {run_proc.stderr}\n"
        f"Stdout: {run_proc.stdout}"
    )


def test_randomized_bounds_and_valid_record_processing():
    source_path = "/home/user/csv_transformer.c"
    installed_binary = "/home/user/csv_transformer"
    assert os.path.isfile(installed_binary), f"Recompiled binary {installed_binary} does not exist."
    assert os.access(installed_binary, os.X_OK), f"Binary {installed_binary} is not executable."

    rng = secrets.SystemRandom()
    valid_ids = [0, 1, 998, 999] + rng.sample(range(2, 998), 12)
    valid = [(record_id, f"Valid_{rng.randrange(1, 10**9)}", rng.randrange(-10000, 10001))
             for record_id in valid_ids]
    invalid_ids = [-1, -2147483648, 1000, 2147483647]
    invalid_ids += [-rng.randrange(2, 1000000) for _ in range(16)]
    invalid_ids += [rng.randrange(1001, 2000000000) for _ in range(16)]
    rows = [f"{record_id},{name},{score}" for record_id, name, score in valid]
    rows += [f"{record_id},Invalid_{i},{rng.randrange(-10000, 10001)}"
             for i, record_id in enumerate(invalid_ids)]
    rng.shuffle(rows)

    with tempfile.TemporaryDirectory() as td:
        csv_path = os.path.join(td, "randomized.csv")
        harness_path = os.path.join(td, "harness.c")
        harness_bin = os.path.join(td, "harness")
        with open(csv_path, "w") as f:
            f.write("\n".join(rows) + "\n")

        expected_entries = ",\n".join(
            f'    {{{record_id}, "{name}", {score}}}'
            for record_id, name, score in valid
        )
        harness = f'''\
#include <stdio.h>
#include <string.h>
#define main submitted_csv_transformer_main
#include "{source_path}"
#undef main

typedef struct {{
    int id;
    const char *name;
    int score;
}} Expected;

static Expected expected[] = {{
{expected_entries}
}};

int main(int argc, char **argv) {{
    if (argc != 2) return 90;
    process_file(argv[1]);

    for (int id = 0; id < 1000; ++id) {{
        Expected *match = NULL;
        for (unsigned long j = 0; j < sizeof(expected) / sizeof(expected[0]); ++j) {{
            if (expected[j].id == id) {{
                match = &expected[j];
                break;
            }}
        }}
        if (match) {{
            if (db[id] == NULL) return 10;
            if (db[id]->id != match->id) return 11;
            if (db[id]->score != match->score) return 12;
            if (strcmp(db[id]->name, match->name) != 0) return 13;
        }} else if (db[id] != NULL) {{
            return 14;
        }}
    }}
    return 0;
}}
'''
        with open(harness_path, "w") as f:
            f.write(harness)

        compile_proc = subprocess.run(
            ["gcc", "-g", "-O0", "-fsanitize=address,undefined",
             "-fno-sanitize-recover=all", "-o", harness_bin, harness_path],
            capture_output=True,
            text=True
        )
        assert compile_proc.returncode == 0, (
            f"Instrumented behavioral harness failed to compile:\n{compile_proc.stderr}"
        )

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        env["UBSAN_OPTIONS"] = "halt_on_error=1"
        run_proc = subprocess.run(
            [harness_bin, csv_path],
            capture_output=True,
            text=True,
            timeout=10,
            env=env
        )
        assert run_proc.returncode == 0, (
            "The source did not process valid records correctly while skipping all "
            "randomized out-of-range IDs.\n"
            f"Exit code: {run_proc.returncode}\n"
            f"Stderr: {run_proc.stderr}\nStdout: {run_proc.stdout}"
        )

        installed_run = subprocess.run(
            [installed_binary, csv_path],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert installed_run.returncode == 0, (
            f"The recompiled /home/user/csv_transformer did not exit cleanly on "
            f"randomized boundary data.\nStderr: {installed_run.stderr}\n"
            f"Stdout: {installed_run.stdout}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
