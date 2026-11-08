#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import math
import secrets
import subprocess
import tempfile
from collections import Counter

SOURCE = "/home/user/simulator.c"
BINARY = "/home/user/simulator"
PARAMS = "/home/user/params.csv"
FASTA = "/home/user/sequences.fasta"
OUTPUT = "/home/user/training_data.tsv"


def reference(r):
    y = 0.1
    t = 0.0
    while t < 5.0:
        dydt = r * y * (1.0 - y / 10.0)
        dt = 0.01 / (1.0 + abs(dydt))
        if dt < 0.0001:
            dt = 0.0001
        if t + dt > 5.0:
            dt = 5.0 - t
        y = y + dydt * dt
        t = t + dt
    return y


def run_simulator(path, r):
    result = subprocess.run(
        [path, format(r, ".17g")],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"{path} failed for r={r}: return code {result.returncode}; "
        f"stderr={result.stderr!r}"
    )
    text = result.stdout.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", text), (
        f"Simulator produced invalid output for r={r}: {result.stdout!r}"
    )
    value = float(text)
    assert math.isfinite(value), f"Simulator produced a non-finite value for r={r}"
    return value


def assert_matches_reference(path, values):
    for r in values:
        actual = run_simulator(path, r)
        expected = reference(r)
        assert abs(actual - expected) <= 5.1e-7, (
            f"Incorrect integration for r={r}: got {actual}, expected output near "
            f"{expected:.6f}"
        )


def strip_c_comments(content):
    content = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    content = re.sub(r"//[^\n]*", "", content)
    return content


def read_params():
    rows = []
    with open(PARAMS, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            fields = [part.strip() for part in line.split(",")]
            assert len(fields) == 2, f"Malformed params row: {line!r}"
            if fields[0] == "Sequence_ID" and fields[1] == "r_value":
                continue
            rows.append((fields[0], float(fields[1])))
    return rows


def read_fasta():
    records = {}
    current = None
    chunks = []
    with open(FASTA, "r") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current is not None:
                    records[current] = "".join(chunks)
                current = line[1:].split()[0]
                chunks = []
            else:
                assert current is not None, "Sequence data appeared before a FASTA header"
                chunks.append(line)
    if current is not None:
        records[current] = "".join(chunks)
    return records


def test_simulator_c_fixed():
    assert os.path.exists(SOURCE), f"File {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "dt = 0.01 / (1.0 + fabs(dydt));" in content, (
        "The step-size adaptation rule was not correctly updated."
    )
    assert "0.0001" in content, "Clamping logic to 0.0001 seems missing."

    # Comments do not count as an implementation.
    active = strip_c_comments(content)
    assert "dt = 0.01 / (1.0 + fabs(dydt));" in active, (
        "The required inverse adaptation statement is only missing or commented out."
    )
    assert "dt = 0.01 * (1.0 + fabs(dydt));" not in active, (
        "The buggy increasing step-size rule is still active."
    )
    clamp = re.compile(
        r"if\s*\(\s*dt\s*<\s*=?\s*0\.0001\s*\)\s*"
        r"(?:\{\s*)?dt\s*=\s*0\.0001\s*;",
        re.S,
    )
    assert clamp.search(active), "Active lower-bound clamping of dt to 0.0001 is missing."


def test_simulator_binary_exists_and_executable():
    assert os.path.exists(BINARY), f"Compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."


def test_source_compiles_and_both_binaries_integrate_correctly():
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "simulator")
        build = subprocess.run(
            ["gcc", "-O2", SOURCE, "-lm", "-o", rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert build.returncode == 0, f"simulator.c does not compile:\n{build.stderr}"

        params = [r for _, r in read_params()]
        # Unpredictable extra inputs prevent a binary hardcoded for the disclosed CSV.
        random_values = [
            0.05 + secrets.randbelow(2950000) / 1000000.0
            for _ in range(5)
        ]
        values = params + [0.0, 3.75] + random_values
        assert_matches_reference(rebuilt, values)
        assert_matches_reference(BINARY, values)


def test_training_data_tsv_content():
    assert os.path.exists(OUTPUT), f"File {OUTPUT} does not exist."

    with open(OUTPUT, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    # Preserve the original expected-content assertions.
    expected_lines = [
        "seq2\tGGGGCCCCTTTTAAAA",
        "seq4\tCGTACGTACGTACGTA",
        "seq5\tAAAACCCC",
    ]
    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {OUTPUT}, found {len(lines)}."
    )
    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in {OUTPUT}."

    # Independently derive the selected records from params.csv, the specified
    # integration algorithm, and sequences.fasta.
    sequences = read_fasta()
    derived = []
    for sequence_id, r in read_params():
        if reference(r) > 2.0:
            assert sequence_id in sequences, f"Missing FASTA record for {sequence_id}"
            derived.append(f"{sequence_id}\t{sequences[sequence_id]}")
    assert Counter(lines) == Counter(derived), (
        f"training_data.tsv does not match the records selected by simulation: {derived}"
    )


def test_training_data_tsv_format():
    assert os.path.exists(OUTPUT), f"File {OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        content = f.read()

    # Preserve the original format assertions.
    assert ">" not in content, "The output file should not contain '>' characters."
    assert "GGGGCCCC\t" not in content and "GGGGCCCC\n" not in content, (
        "Sequences were not properly concatenated on a single line."
    )

    for line in content.splitlines():
        if not line:
            continue
        fields = line.split("\t")
        assert len(fields) == 2, f"Each output line must have exactly two TSV fields: {line!r}"
        assert fields[0] and fields[1], f"Empty ID or sequence in output line: {line!r}"
        assert not re.search(r"\s", fields[1]), f"Sequence contains whitespace: {line!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
