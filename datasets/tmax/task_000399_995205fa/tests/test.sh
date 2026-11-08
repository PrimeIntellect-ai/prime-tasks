#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/seq_analyzer"
SOURCE = "/home/user/seq_analyzer.c"
DATASET = "/home/user/dataset.fasta"
OUTPUT = "/home/user/analysis_output.txt"


def parse_output(raw):
    text = raw.decode("utf-8") if isinstance(raw, bytes) else raw
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert len(lines) == 3, f"Expected exactly 3 lines of output, found {len(lines)}."
    assert lines[0].startswith("Fitted Mean:"), "First line must start with 'Fitted Mean:'"
    assert lines[1].startswith("Fitted Variance:"), "Second line must start with 'Fitted Variance:'"
    assert lines[2].startswith("Z-score:"), "Third line must start with 'Z-score:'"
    assert re.fullmatch(r"Fitted Mean: [-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", lines[0])
    assert re.fullmatch(r"Fitted Variance: [-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", lines[1])
    assert re.fullmatch(r"Z-score: [-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", lines[2])
    try:
        values = tuple(float(line.split(":", 1)[1].strip()) for line in lines)
    except ValueError:
        pytest.fail("Could not parse numeric values from the output.")
    assert all(math.isfinite(v) for v in values), "Output contains a non-finite value."
    return values


def read_gc_contents(path):
    values = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(">"):
                continue
            values.append(sum(c in ("G", "C") for c in line) / len(line))
    return values


def expected_values(gc_contents, iterations=500):
    n = len(gc_contents)
    assert n > 0
    mu = 0.5
    alpha = 0.8 / n
    for _ in range(iterations):
        grad = sum(x - mu for x in gc_contents)
        mu = mu + alpha * grad
    var = sum((x - mu) ** 2 for x in gc_contents) / n
    if var < 1e-9:
        var = 1e-9
    z = (mu - 0.5) / math.sqrt(var / n)
    return mu, var, z


def assert_values_close(actual, expected):
    for name, got, want in zip(("Fitted Mean", "Fitted Variance", "Z-score"), actual, expected):
        assert math.isclose(got, want, rel_tol=1e-7, abs_tol=1e-3), \
            f"Expected {name} ~{want:.4f}, got {got}"


def make_random_fasta():
    rng = random.SystemRandom()
    n = rng.randint(4, 15)
    records = []
    values = []
    for i in range(n):
        length = rng.randint(20, 80)
        gc = rng.randint(0, length)
        chars = ["G"] * gc + ["A"] * (length - gc)
        rng.shuffle(chars)
        sequence = "".join(chars)
        records.append(f">random_{i}\n{sequence}\n")
        values.append(gc / length)
    return "".join(records), values


def run_with_dataset(program, fasta_text):
    with open(DATASET, "rb") as f:
        original = f.read()
    try:
        with open(DATASET, "w") as f:
            f.write(fasta_text)
        result = subprocess.run([program], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=10, check=False)
        assert result.returncode == 0, \
            f"Program failed with exit code {result.returncode}: {result.stderr.decode(errors='replace')}"
        return result.stdout
    finally:
        with open(DATASET, "wb") as f:
            f.write(original)


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing. Did you compile the C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "seq_analyzer must be a compiled executable, not a script or text file."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing. Did you redirect the output?"


def test_output_values():
    assert os.path.isfile(DATASET), f"Dataset file {DATASET} is missing."
    gc_contents = read_gc_contents(DATASET)
    assert gc_contents, "No sequences found in dataset."

    expected_mu = sum(gc_contents) / len(gc_contents)
    expected_var = sum((x - expected_mu) ** 2 for x in gc_contents) / len(gc_contents)
    if expected_var < 1e-9:
        expected_var = 1e-9
    expected_z = (expected_mu - 0.5) / math.sqrt(expected_var / len(gc_contents))

    with open(OUTPUT, "rb") as f:
        actual = parse_output(f.read())
    assert_values_close(actual, (expected_mu, expected_var, expected_z))


def test_output_is_exact_program_stdout():
    result = subprocess.run([EXECUTABLE], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=10, check=False)
    assert result.returncode == 0, \
        f"seq_analyzer failed with exit code {result.returncode}: {result.stderr.decode(errors='replace')}"
    with open(OUTPUT, "rb") as f:
        saved_output = f.read()
    assert saved_output == result.stdout, \
        "analysis_output.txt is not the exact standard output produced by /home/user/seq_analyzer."


def test_executable_handles_runtime_derived_dataset():
    fasta, gc_contents = make_random_fasta()
    stdout = run_with_dataset(EXECUTABLE, fasta)
    assert_values_close(parse_output(stdout), expected_values(gc_contents, 500))


def test_c_code_fixed():
    assert os.path.isfile(SOURCE), f"Missing C source file: {SOURCE}"
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original assertion against the supplied buggy statement.
    assert "mu = mu + alpha * grad;" not in content, \
        "The C file still contains the buggy update rule without dividing by n."

    # Compile an instrumented one-iteration copy. This directly checks that the
    # effective update made by the submitted source is 0.8/n rather than merely
    # accepting a cosmetic source edit whose 500-iteration output was fabricated.
    loop = re.compile(r"for\s*\(\s*int\s+iter\s*=\s*0\s*;\s*iter\s*<\s*500\s*;\s*iter\s*\+\+\s*\)")
    instrumented, count = loop.subn("for(int iter=0; iter<1; iter++)", content, count=1)
    assert count == 1, "Could not locate the supplied 500-iteration density fitting loop."

    with tempfile.TemporaryDirectory() as td:
        source_copy = os.path.join(td, "seq_analyzer_one_iter.c")
        binary = os.path.join(td, "seq_analyzer_one_iter")
        with open(source_copy, "w") as f:
            f.write(instrumented)
        build = subprocess.run(["gcc", source_copy, "-o", binary, "-lm"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        assert build.returncode == 0, \
            f"The modified C source does not compile with the math library: {build.stderr.decode(errors='replace')}"

        fasta, gc_contents = make_random_fasta()
        stdout = run_with_dataset(binary, fasta)
        assert_values_close(parse_output(stdout), expected_values(gc_contents, 1))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
