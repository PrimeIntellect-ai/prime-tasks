#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import pytest

SANITIZER = "/home/user/sanitize_reads.sh"
FINDER = "/home/user/find_optimal_k.sh"
OPTIMAL = "/home/user/optimal_k.txt"
SAMPLE = "/data/sample_reads.fasta"
CLEAN_SAMPLE = "/tmp/clean_sample.fasta"
BINARY = "/app/bin/debruijn_mpi"


def records(raw):
    """Split valid test FASTA bytes into complete record byte strings."""
    lines = raw.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.startswith(b">")]
    assert starts and starts[0] == 0
    starts.append(len(lines))
    return [b"".join(lines[starts[i]:starts[i + 1]]) for i in range(len(starts) - 1)]


def sequence(record):
    lines = record.splitlines()
    return b"".join(lines[1:])


def evil(seq):
    return b"N" in seq.upper() or re.search(rb"(.)\1{20,}", seq) is not None


def run_sanitizer(raw):
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "input.fasta")
        dst = os.path.join(td, "output.fasta")
        with open(src, "wb") as f:
            f.write(raw)
        subprocess.run([SANITIZER, src, dst], check=True, timeout=10)
        assert os.path.isfile(dst), "sanitizer did not create its output"
        with open(dst, "rb") as f:
            return f.read()


def expected(raw):
    return b"".join(r for r in records(raw) if not evil(sequence(r)))


def test_scripts_executable():
    for path in (SANITIZER, FINDER):
        assert os.path.isfile(path), f"Missing {path}"
        assert os.access(path, os.X_OK), f"{path} is not executable"


def test_adversarial_corpus():
    # Preserve the original corpus assertions, including exact sequence checks.
    for directory in ("/app/corpus/evil", "/app/corpus/clean"):
        for name in os.listdir(directory):
            if not name.endswith(".fasta"):
                continue
            path = os.path.join(directory, name)
            with open(path, "rb") as f:
                raw = f.read()
            assert run_sanitizer(raw) == expected(raw), f"incorrect output for {path}"


def test_sanitizer_hidden_edge_cases_and_exact_bytes():
    # Generated after the agent has finished; headers and formatting are not from
    # the fixed setup corpus. Valid records must survive byte-for-byte and in order.
    token = os.urandom(8).hex().encode()
    cases = [
        (b">keep_" + token + b" description with spaces\r\nACgtACGT\r\n", True),
        (b">has_upper_n_" + token + b"\nACGTNACGT\n", False),
        (b">has_lower_n_" + token + b"\nacgtnacgt\n", False),
        (b">twenty_ok_" + token + b"\n" + b"C" * 20 + b"A\n", True),
        (b">twentyone_bad_" + token + b"\nT" + b"G" * 21 + b"C\n", False),
        (b">multiline_cross_bad_" + token + b"\n" + b"A" * 12 + b"\n" + b"A" * 9 + b"\n", False),
        (b">multiline_keep_" + token + b" extra\nACGTAC\nTGCA\n", True),
        (b">final_no_newline_" + token + b"\nGATTACA", True),
    ]
    raw = b"".join(record for record, _ in cases)
    want = b"".join(record for record, keep in cases if keep)
    assert run_sanitizer(raw) == want


def binary_components(k, fasta):
    env = os.environ.copy()
    env["OMPI_ALLOW_RUN_AS_ROOT"] = "1"
    env["OMPI_ALLOW_RUN_AS_ROOT_CONFIRM"] = "1"
    p = subprocess.run(
        ["mpirun", "-np", "4", BINARY, "-k", str(k), fasta],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20, env=env)
    values = re.findall(r"(?m)^\s*(-?\d+)\s*$", p.stdout)
    assert values, f"binary produced no integer for k={k}: {p.stdout!r}"
    return int(values[-1])


def derive_optimal():
    # Derive the answer from actual binary executions rather than trusting a
    # fixed expected string.
    k = 15
    for _ in range(100):
        if binary_components(k, CLEAN_SAMPLE) == 1:
            return k
        k += 2
    pytest.fail("binary did not converge within verifier bound")


def test_find_optimal_k_is_executed_and_computes_result():
    for path in (OPTIMAL, CLEAN_SAMPLE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    subprocess.run([FINDER], check=True, timeout=120)
    assert os.path.isfile(CLEAN_SAMPLE), f"{FINDER} did not create {CLEAN_SAMPLE}"
    with open(SAMPLE, "rb") as f:
        sample = f.read()
    with open(CLEAN_SAMPLE, "rb") as f:
        cleaned = f.read()
    assert cleaned == expected(sample), "find script did not correctly sanitize the sample"

    assert os.path.isfile(OPTIMAL), f"Missing {OPTIMAL} after executing {FINDER}"
    with open(OPTIMAL, "rb") as f:
        content = f.read()
    assert re.fullmatch(rb"\s*\d+\s*", content), "optimal_k.txt must contain only a k value"
    actual = int(content.strip())
    assert actual >= 15 and actual % 2 == 1
    assert actual == derive_optimal(), "reported k is not the first odd converged k"
    assert binary_components(actual, CLEAN_SAMPLE) == 1
    assert actual == 15 or binary_components(actual - 2, CLEAN_SAMPLE) != 1
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
