#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import struct
import subprocess
import tempfile

import numpy as np
import pytest

ANALYZE = "/home/user/analyze.py"
PARSER = "/home/user/parser"
DATA = "/home/user/data.fasta"
RESULT = "/home/user/result.json"


def run_analyze():
    if os.path.exists(RESULT):
        os.unlink(RESULT)
    proc = subprocess.run(
        ["python3", ANALYZE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, (
        f"analyze.py failed with exit code {proc.returncode}\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.isfile(RESULT), "analyze.py did not create /home/user/result.json"


def load_result():
    with open(RESULT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT} is not valid JSON.")


@pytest.fixture(scope="session", autouse=True)
def execute_submission_on_original_input():
    run_analyze()


def test_parser_executable_exists():
    path = "/home/user/parser"
    assert os.path.isfile(path), f"Missing compiled executable: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The parser is not a compiled native executable"


def test_analyze_py_updated():
    path = "/home/user/analyze.py"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "parser" in content, "The script /home/user/analyze.py does not seem to call the 'parser' executable."
    assert "np.fromfile" in content or "fromfile" in content or "open" in content, "The script does not seem to read the binary file."


def test_result_json_exists_and_correct():
    path = "/home/user/result.json"
    assert os.path.isfile(path), f"Missing result file: {path}"
    data = load_result()

    assert "peak_index" in data, "Missing key 'peak_index' in result.json"
    assert "peak_magnitude" in data, "Missing key 'peak_magnitude' in result.json"

    assert data["peak_index"] == 25000, f"Expected peak_index to be 25000, got {data['peak_index']}"
    assert abs(data["peak_magnitude"] - 70710.7) < 0.1, f"Expected peak_magnitude to be 70710.7, got {data['peak_magnitude']}"


def test_compiled_parser_converts_fasta_to_float32():
    rng = np.random.default_rng(secrets.randbits(64))
    alphabet = np.array(list("AGCT"))
    sequence = "".join(rng.choice(alphabet, size=733).tolist())
    expected = np.array([1.0 if c in "AG" else -1.0 for c in sequence], dtype=np.float32)

    with tempfile.TemporaryDirectory() as td:
        fasta = os.path.join(td, "input.fasta")
        output = os.path.join(td, "output.bin")
        with open(fasta, "w") as f:
            f.write(">random sequence\n")
            for i in range(0, len(sequence), 47):
                f.write(sequence[i:i + 47] + "\n")

        proc = subprocess.run(
            [PARSER, fasta, output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert proc.returncode == 0, f"parser failed with exit code {proc.returncode}: {proc.stderr!r}"
        assert os.path.isfile(output), "parser did not create its requested binary output"
        actual = np.fromfile(output, dtype=np.float32)
        assert actual.dtype == np.float32
        assert np.array_equal(actual, expected), "parser output does not match the FASTA purine/pyrimidine mapping"


def test_analyze_invokes_parser_and_loads_its_binary_output():
    original_data = open(DATA, "rb").read()
    parser_backup = PARSER + ".verifier_backup"
    marker = "/tmp/parser_invocation_marker"
    wrapper_src = "/tmp/verifier_parser_wrapper.c"

    rng = np.random.default_rng(secrets.randbits(64))
    supplied = rng.normal(size=257).astype(np.float32)
    bit_values = supplied.view(np.uint32)
    initializer = ",".join(f"0x{int(v):08x}u" for v in bit_values)
    c_source = f'''\
#include <stdint.h>
#include <stdio.h>
int main(int argc, char **argv) {{
    if (argc != 3) return 91;
    FILE *mark = fopen("{marker}", "w");
    if (!mark) return 92;
    fprintf(mark, "%s\\n%s\\n", argv[1], argv[2]);
    fclose(mark);
    uint32_t values[] = {{{initializer}}};
    FILE *out = fopen(argv[2], "wb");
    if (!out) return 93;
    size_t count = sizeof(values) / sizeof(values[0]);
    if (fwrite(values, sizeof(uint32_t), count, out) != count) return 94;
    fclose(out);
    return 0;
}}
'''

    if os.path.exists(marker):
        os.unlink(marker)
    if os.path.exists(parser_backup):
        os.unlink(parser_backup)

    os.replace(PARSER, parser_backup)
    try:
        with open(wrapper_src, "w") as f:
            f.write(c_source)
        subprocess.run(["gcc", "-O2", wrapper_src, "-o", PARSER], check=True, timeout=20)
        os.chmod(PARSER, 0o755)

        probe_sequence = "ACGTGCAATTCG" * 31
        with open(DATA, "w") as f:
            f.write(">verification_probe\n")
            for i in range(0, len(probe_sequence), 29):
                f.write(probe_sequence[i:i + 29] + "\n")

        run_analyze()
        data = load_result()

        assert os.path.isfile(marker), "analyze.py did not invoke /home/user/parser"
        with open(marker, "r") as f:
            invocation = f.read().splitlines()
        assert len(invocation) == 2, "parser was not invoked with exactly an input and output path"
        assert os.path.realpath(invocation[0]) == os.path.realpath(DATA), "analyze.py passed the wrong FASTA input to parser"
        assert invocation[1] != invocation[0], "analyze.py did not request a separate binary output file"

        mags = np.abs(np.fft.fft(supplied))
        mags[0] = 0
        max_mag = float(np.max(mags))
        valid_indices = set(np.flatnonzero(np.isclose(mags, max_mag, rtol=1e-12, atol=1e-9)).tolist())
        expected_rounded = float(f"{max_mag:.1f}")

        assert set(data.keys()) == {"peak_index", "peak_magnitude"}, "result.json must contain exactly the required keys"
        assert type(data["peak_index"]) is int, "peak_index must be an integer"
        assert isinstance(data["peak_magnitude"], (int, float)) and not isinstance(data["peak_magnitude"], bool), "peak_magnitude must be numeric"
        assert data["peak_index"] in valid_indices, (
            f"FFT peak index does not match the binary floats emitted by parser: got {data['peak_index']}"
        )
        assert abs(float(data["peak_magnitude"]) - expected_rounded) < 0.051, (
            f"FFT peak magnitude does not match parser output: expected {expected_rounded}, got {data['peak_magnitude']}"
        )
    finally:
        if os.path.exists(PARSER):
            os.unlink(PARSER)
        if os.path.exists(parser_backup):
            os.replace(parser_backup, PARSER)
        with open(DATA, "wb") as f:
            f.write(original_data)
        if os.path.exists(marker):
            os.unlink(marker)
        if os.path.exists(wrapper_src):
            os.unlink(wrapper_src)
        # Leave the task artifacts in their required state.
        if os.path.isfile(PARSER) and os.path.isfile(ANALYZE):
            run_analyze()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
