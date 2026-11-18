#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess

import numpy as np
import pytest


def test_cleaner_c_exists():
    assert os.path.isfile("/home/user/cleaner.c"), "/home/user/cleaner.c does not exist"


def test_test_pipeline_sh_exists_and_executable():
    script_path = "/home/user/test_pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"


def test_pipeline_execution():
    script_path = "/home/user/test_pipeline.sh"
    result = subprocess.run(["bash", script_path], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"test_pipeline.sh failed with exit code {result.returncode}. stderr: {result.stderr}"
    assert "PASS: Reproducible" in result.stdout, f"test_pipeline.sh did not print 'PASS: Reproducible'. stdout: {result.stdout}"

    executable = "/home/user/cleaner"
    first_path = "/home/user/clean_embeddings.csv"
    second_path = "/home/user/clean_embeddings_run2.csv"
    assert os.path.isfile(executable), "test_pipeline.sh did not compile /home/user/cleaner"
    assert os.access(executable, os.X_OK), "/home/user/cleaner is not executable"
    assert os.path.isfile(first_path), "First pipeline output is missing"
    assert os.path.isfile(second_path), "Second pipeline output is missing"
    with open(first_path, "rb") as first, open(second_path, "rb") as second:
        assert first.read() == second.read(), "The two pipeline outputs are not byte-for-byte identical"


def test_clean_embeddings_output():
    orig_path = "/home/user/data/embeddings.csv"
    clean_path = "/home/user/clean_embeddings.csv"

    assert os.path.isfile(orig_path), f"Original data {orig_path} missing"
    assert os.path.isfile(clean_path), f"Cleaned data {clean_path} missing"

    with open(orig_path, 'r') as f:
        orig_lines = [line.strip() for line in f if line.strip()]

    with open(clean_path, 'r') as f:
        clean_lines = [line.strip() for line in f if line.strip()]

    assert len(clean_lines) == 50, f"Expected 50 rows in cleaned data, got {len(clean_lines)}"

    expected_cols = [0, 1, 2, 4, 5, 6, 8, 9]

    for i, (orig_line, clean_line) in enumerate(zip(orig_lines, clean_lines)):
        orig_vals = [float(x) for x in orig_line.split(',')]
        clean_vals = [float(x) for x in clean_line.split(',')]

        assert len(clean_vals) == 8, f"Row {i} in cleaned data does not have exactly 8 columns"

        for new_idx, old_idx in enumerate(expected_cols):
            diff = abs(clean_vals[new_idx] - orig_vals[old_idx])
            assert diff < 1e-5, f"Value mismatch in row {i}, new col {new_idx} (old col {old_idx}). Expected ~{orig_vals[old_idx]}, got {clean_vals[new_idx]}"


def retained_columns(data):
    dropped = [False] * data.shape[1]
    for i in range(data.shape[1]):
        for j in range(i + 1, data.shape[1]):
            corr = np.corrcoef(data[:, i], data[:, j])[0, 1]
            if abs(corr) > 0.85:
                dropped[j] = True
    return [i for i, is_dropped in enumerate(dropped) if not is_dropped]


def assert_clean_output(input_data, output_path):
    assert os.path.isfile(output_path), "cleaner did not create /home/user/clean_embeddings.csv"
    expected_cols = retained_columns(input_data)

    with open(output_path, "r", newline="") as f:
        raw_lines = f.read().splitlines()

    assert len(raw_lines) == input_data.shape[0], f"Expected {input_data.shape[0]} output rows, got {len(raw_lines)}"
    number = re.compile(r"^-?(?:0|[1-9][0-9]*)\.[0-9]{6}$")
    for row_index, line in enumerate(raw_lines):
        assert not line.endswith(','), f"Row {row_index} has a trailing comma"
        fields = line.split(',')
        assert len(fields) == len(expected_cols), (
            f"Row {row_index} has {len(fields)} columns; expected {len(expected_cols)} "
            f"after retaining columns {expected_cols}"
        )
        for output_index, source_index in enumerate(expected_cols):
            field = fields[output_index]
            assert number.fullmatch(field), f"Value {field!r} is not printed with exactly six decimal places"
            expected_text = f"{input_data[row_index, source_index]:.6f}"
            assert field == expected_text, (
                f"Row {row_index}, output column {output_index} should contain source column "
                f"{source_index} as {expected_text}, got {field}"
            )


def test_cleaner_computes_correlations_on_unseen_inputs():
    source = "/home/user/cleaner.c"
    executable = "/tmp/cleaner_verifier"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", source, "-o", executable, "-lm"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"cleaner.c failed to compile: {compile_result.stderr}"

    input_path = "/home/user/data/embeddings.csv"
    output_path = "/home/user/clean_embeddings.csv"
    backup_path = "/tmp/original_embeddings.csv"
    shutil.copyfile(input_path, backup_path)

    try:
        system_rng = secrets.SystemRandom()
        for trial in range(3):
            # Generate a fresh, unknown layout of correlated columns. The values are
            # rounded before deriving the answer, exactly as they are in the CSV read by C.
            for _ in range(100):
                seed = secrets.randbits(64)
                rng = np.random.default_rng(seed)
                data = rng.normal(size=(50, 10))
                targets = system_rng.sample(list(range(3, 10)), 3)
                for target in targets:
                    possible_sources = [i for i in range(target) if i not in targets]
                    source_col = system_rng.choice(possible_sources)
                    sign = system_rng.choice([-1.0, 1.0])
                    scale = system_rng.uniform(0.7, 2.4)
                    data[:, target] = sign * scale * data[:, source_col] + rng.normal(0, 0.015, 50)
                data = np.round(data, 6)
                if retained_columns(data) != [0, 1, 2, 4, 5, 6, 8, 9]:
                    break
            else:
                pytest.fail("Could not construct a dynamic correlation test case")

            np.savetxt(input_path, data, delimiter=",", fmt="%.6f")
            if os.path.exists(output_path):
                os.remove(output_path)
            result = subprocess.run([executable], cwd="/home/user", capture_output=True, text=True, timeout=15)
            assert result.returncode == 0, (
                f"Compiled cleaner failed on unseen input in trial {trial}: "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert_clean_output(data, output_path)
    finally:
        shutil.copyfile(backup_path, input_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
