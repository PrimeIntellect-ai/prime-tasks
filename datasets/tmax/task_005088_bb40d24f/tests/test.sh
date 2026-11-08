#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import importlib.util
import math
import os
import stat
import subprocess
import sys
import pytest

BUILDER_PATH = "/home/user/builder.py"
OUTPUT_PATH = "/home/user/decay_table.txt"


def test_builder_exists_and_computes_correctly():
    """Check the requested build script itself and exercise its computation."""
    assert os.path.exists(BUILDER_PATH), f"File {BUILDER_PATH} is missing."
    assert os.path.isfile(BUILDER_PATH), f"Path {BUILDER_PATH} is not a regular file."

    spec = importlib.util.spec_from_file_location("submitted_builder", BUILDER_PATH)
    assert spec is not None and spec.loader is not None, "builder.py is not loadable as Python."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    assert hasattr(module, "compute_decay_table"), "compute_decay_table is missing."
    assert callable(module.compute_decay_table), "compute_decay_table is not callable."

    # Exercise multiple boundaries, including a runtime-selected size, so the
    # implementation—not a pre-created output file—must perform the computation.
    runtime_n = 2 + int.from_bytes(os.urandom(2), "big") % 97
    for n in (0, 1, 2, 50, runtime_n):
        table = module.compute_decay_table(n)
        assert len(table) == n, f"compute_decay_table({n}) returned {len(table)} elements."
        for i, actual in enumerate(table):
            expected = math.exp(-i / 10.0)
            assert actual == expected, (
                f"compute_decay_table({n})[{i}] expected full-precision {expected!r}, "
                f"got {actual!r}."
            )

    # Remove any pre-created answer and require builder.py to regenerate it.
    if os.path.lexists(OUTPUT_PATH):
        if os.path.isdir(OUTPUT_PATH) and not os.path.islink(OUTPUT_PATH):
            pytest.fail(f"Path {OUTPUT_PATH} is a directory, not an output file.")
        os.unlink(OUTPUT_PATH)

    result = subprocess.run(
        [sys.executable, BUILDER_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Executing {BUILDER_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_decay_table_exists():
    """Check that /home/user/decay_table.txt exists and is a file."""
    path = "/home/user/decay_table.txt"
    assert os.path.exists(path), f"File {path} was not generated."
    assert os.path.isfile(path), f"Path {path} is not a regular file."


def test_decay_table_content():
    """Check that /home/user/decay_table.txt contains exactly the expected 50 values."""
    path = "/home/user/decay_table.txt"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 50, f"Expected exactly 50 lines in {path}, but found {len(lines)}."

    for i in range(50):
        expected_val = math.exp(-i / 10.0)
        expected_str = f"{expected_val:.6f}"
        actual_str = lines[i].strip()

        assert actual_str == expected_str, (
            f"Line {i+1} mismatch: expected '{expected_str}', got '{actual_str}'. "
            "Ensure the precision loss issue and boundary errors are fixed."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
