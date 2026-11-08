#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import struct
import subprocess
import tempfile

import pytest

PIPELINE_C = "/home/user/pipeline.c"
PIPELINE_EXE = "/home/user/pipeline"
OUTPUT = "/home/user/output.txt"


def f32(value):
    return struct.unpack("f", struct.pack("f", value))[0]


def expected_result(entries):
    values = [f32(0.0), f32(0.0), f32(0.0)]
    for ident, value in entries:
        value = f32(value)
        if 0 <= ident < 3:
            values[ident] = f32(values[ident] + value)

    diff = f32(100.0)
    iterations = 0
    while diff > 0.001 and iterations < 1000:
        old_val = values[0]
        summed = f32(f32(values[0] + values[1]) + values[2])
        values[0] = f32(summed / f32(3.0))
        diff = f32(abs(f32(old_val - values[0])))
        iterations += 1

    return (
        f"Final State: {values[0]:.3f} {values[1]:.3f} {values[2]:.3f}",
        f"Iterations: {iterations}",
    )


def remove_output():
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)


def run_pipeline(executable, data_dir):
    remove_output()
    env = os.environ.copy()
    env["DATA_DIR"] = data_dir
    result = subprocess.run(
        [executable],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"{executable} failed with status {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), (
        f"{executable} did not freshly generate {OUTPUT}"
    )
    with open(OUTPUT, "r") as f:
        return f.read()


def assert_exact_output(content, expected_state, expected_iters):
    match = re.fullmatch(
        r"\s*Final State: ([^\n]+)\nIterations: ([0-9]+)\s*", content
    )
    assert match, f"Unexpected output.txt format: {content!r}"
    assert expected_state in content, (
        f"output.txt does not contain the correct final state. "
        f"Expected: '{expected_state}'"
    )
    assert expected_iters in content, (
        f"output.txt does not contain the correct iterations count. "
        f"Expected: '{expected_iters}'"
    )


def test_pipeline_c_fixed():
    pipeline_path = PIPELINE_C
    assert os.path.isfile(pipeline_path), f"File {pipeline_path} does not exist."

    with open(pipeline_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "exit(1)" not in content[content.find("sscanf") : content.find("if (id >=")] or "continue" in content, \
        "pipeline.c still aborts on WAL corruption instead of ignoring the line."

    assert "fabs(" in content or "abs(" in content or "(old_val - values[0] < 0" in content or "diff = values[0] - old_val" in content, \
        "pipeline.c does not seem to calculate the absolute difference in the convergence loop."


def test_pipeline_executable_exists():
    exe_path = PIPELINE_EXE
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled ELF executable."


def test_pipeline_execution_and_output():
    # Independently compile the submitted C source so the tested behavior must
    # also be present in pipeline.c, rather than only in an unrelated executable.
    rebuilt = "/tmp/pipeline_from_submitted_source"
    compile_result = subprocess.run(
        ["gcc", "-O0", "-o", rebuilt, PIPELINE_C, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert compile_result.returncode == 0, (
        f"pipeline.c did not compile: {compile_result.stderr}"
    )

    # Preserve the original fixed-data output assertions, but only after
    # actually executing the submitted pipeline artifact.
    content = run_pipeline(PIPELINE_EXE, "/home/user/data")
    values = [20.0, 10.0, -5.5]
    diff = 100.0
    iterations = 0
    while diff > 0.001 and iterations < 1000:
        old_val = values[0]
        values[0] = (values[0] + values[1] + values[2]) / 3.0
        diff = abs(old_val - values[0])
        iterations += 1
    expected_state = f"Final State: {values[0]:.3f} {values[1]:.3f} {values[2]:.3f}"
    expected_iters = f"Iterations: {iterations}"
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist. Did you run the pipeline?"
    assert_exact_output(content, expected_state, expected_iters)

    # Exercise both the submitted executable and a fresh build of pipeline.c
    # against unpredictable WAL contents containing malformed records.
    rng = secrets.SystemRandom()
    cases = []
    for _ in range(4):
        entries = [
            (0, float(rng.randint(-80, 80))),
            (1, float(rng.randint(-80, 80))),
            (2, float(rng.randint(-80, 80))),
            (rng.randrange(3), float(rng.randint(-40, 40))),
            (rng.randrange(3), float(rng.randint(-40, 40))),
        ]
        lines = [
            f"{entries[0][0]} {entries[0][1]:.1f}",
            "CORRUPT_ENTRY_XYZ 999",
            f"{entries[1][0]} {entries[1][1]:.1f}",
            "2 not_a_float",
            f"{entries[2][0]} {entries[2][1]:.1f}",
            "malformed",
            f"{entries[3][0]} {entries[3][1]:.1f}",
            f"{entries[4][0]} {entries[4][1]:.1f}",
        ]
        cases.append((entries, "\n".join(lines) + "\n"))

    for executable in (PIPELINE_EXE, rebuilt):
        for entries, wal_text in cases:
            with tempfile.TemporaryDirectory(prefix="pipeline-data-") as data_dir:
                with open(os.path.join(data_dir, "wal.log"), "w") as wal:
                    wal.write(wal_text)
                expected_state, expected_iters = expected_result(entries)
                content = run_pipeline(executable, data_dir)
                assert_exact_output(content, expected_state, expected_iters)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
