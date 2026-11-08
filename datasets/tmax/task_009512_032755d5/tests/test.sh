#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

C_SOURCE = "/home/user/analyze.c"
EXECUTABLE = "/home/user/analyze"
RESULT = "/home/user/analysis_result.txt"
SEQ1 = "/home/user/data/seq1.fasta"
SEQ2 = "/home/user/data/seq2.fasta"
TOLERANCE = 0.000002


def parse_result(strict=False):
    assert os.path.exists(RESULT), f"Result file missing: {RESULT}"
    assert os.path.isfile(RESULT), f"Path is not a file: {RESULT}"
    with open(RESULT, "r") as f:
        content = f.read().strip().split("\n")
    assert len(content) == 4, f"Expected exactly 4 lines in {RESULT}, found {len(content)}"

    number = r"([0-9]+\.[0-9]{6})" if strict else r"([0-9.]+)"
    seq1_match = re.fullmatch(
        rf"Seq1 Dist:\s*A={number},\s*C={number},\s*G={number},\s*T={number}",
        content[0],
    )
    assert seq1_match, f"Line 1 format incorrect: {content[0]}"
    seq2_match = re.fullmatch(
        rf"Seq2 Dist:\s*A={number},\s*C={number},\s*G={number},\s*T={number}",
        content[1],
    )
    assert seq2_match, f"Line 2 format incorrect: {content[1]}"
    db_match = re.fullmatch(rf"Bhattacharyya Distance:\s*{number}", content[2])
    assert db_match, f"Line 3 format incorrect: {content[2]}"
    k_match = re.fullmatch(rf"Mutation Factor k:\s*{number}", content[3])
    assert k_match, f"Line 4 format incorrect: {content[3]}"

    return (
        [float(x) for x in seq1_match.groups()],
        [float(x) for x in seq2_match.groups()],
        float(db_match.group(1)),
        float(k_match.group(1)),
    )


def expected_values(counts1, counts2):
    p = [x / sum(counts1) for x in counts1]
    q = [x / sum(counts2) for x in counts2]
    coefficient = sum(math.sqrt(a * b) for a, b in zip(p, q))
    distance = -math.log(coefficient)

    lo, hi = 0.0, 1.0
    while hi ** 3 + 2.0 * hi < distance:
        hi *= 2.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        if mid ** 3 + 2.0 * mid < distance:
            lo = mid
        else:
            hi = mid
    k = (lo + hi) / 2.0
    return p, q, distance, k


def make_fasta(counts, rng, label):
    bases = "ACGT"
    symbols = []
    for base, count in zip(bases, counts):
        for _ in range(count):
            symbols.append(base.lower() if rng.randrange(2) else base)
    rng.shuffle(symbols)

    lines = [f">{label}_HEADER_ACGT_acgt_MUST_BE_IGNORED"]
    pos = 0
    while pos < len(symbols):
        width = rng.randint(5, 17)
        chunk = symbols[pos:pos + width]
        pos += width
        # These separators contain no A/C/G/T and therefore must be ignored.
        lines.append(" ".join(["".join(chunk[:len(chunk)//2]), "nn#" + "".join(chunk[len(chunk)//2:])]))
    return "\n".join(lines) + "\n"


def run_case(program, counts1, counts2, rng, case_id):
    with open(SEQ1, "w") as f:
        f.write(make_fasta(counts1, rng, f"random_seq1_{case_id}"))
    with open(SEQ2, "w") as f:
        f.write(make_fasta(counts2, rng, f"random_seq2_{case_id}"))

    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        [program], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"{program} failed on generated input: {completed.stderr}"
    )
    assert os.path.isfile(RESULT), f"{program} did not create {RESULT}"

    actual_p, actual_q, actual_db, actual_k = parse_result(strict=True)
    expected_p, expected_q, expected_db, expected_k = expected_values(counts1, counts2)
    for actual, expected in zip(actual_p, expected_p):
        assert math.isclose(actual, expected, abs_tol=TOLERANCE), (
            f"Seq1 generated distribution incorrect: {actual} != {expected}"
        )
    for actual, expected in zip(actual_q, expected_q):
        assert math.isclose(actual, expected, abs_tol=TOLERANCE), (
            f"Seq2 generated distribution incorrect: {actual} != {expected}"
        )
    assert math.isclose(actual_db, expected_db, abs_tol=TOLERANCE), (
        f"Generated Bhattacharyya distance incorrect: {actual_db} != {expected_db}"
    )
    assert math.isclose(actual_k, expected_k, abs_tol=TOLERANCE), (
        f"Generated mutation factor incorrect: {actual_k} != {expected_k}"
    )


def test_final_state():
    # Preserve the original verifier's artifact assertions.
    assert os.path.exists(C_SOURCE), f"C source file missing: {C_SOURCE}"
    assert os.path.isfile(C_SOURCE), f"Path is not a file: {C_SOURCE}"
    assert os.path.exists(EXECUTABLE), f"Executable missing: {EXECUTABLE}"
    assert os.path.isfile(EXECUTABLE), f"Path is not a file: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"Executable is not executable: {EXECUTABLE}"
    assert os.path.exists(RESULT), f"Result file missing: {RESULT}"
    assert os.path.isfile(RESULT), f"Path is not a file: {RESULT}"

    # Preserve the original fixed-input result assertions.
    seq1_vals, seq2_vals, db_val, k_val = parse_result()
    expected_seq1 = [0.200000, 0.300000, 0.400000, 0.100000]
    expected_seq2 = [0.400000, 0.100000, 0.200000, 0.300000]
    for actual, expected in zip(seq1_vals, expected_seq1):
        assert math.isclose(actual, expected, abs_tol=TOLERANCE)
    for actual, expected in zip(seq2_vals, expected_seq2):
        assert math.isclose(actual, expected, abs_tol=TOLERANCE)
    assert math.isclose(db_val, 0.092010, abs_tol=TOLERANCE)
    assert math.isclose(k_val, 0.045981, abs_tol=TOLERANCE)

    with open(SEQ1, "r") as f:
        original_seq1 = f.read()
    with open(SEQ2, "r") as f:
        original_seq2 = f.read()

    rebuilt = "/tmp/analyze_from_source"
    compilation = subprocess.run(
        ["gcc", C_SOURCE, "-o", rebuilt, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compilation.returncode == 0, f"analyze.c does not compile: {compilation.stderr}"

    rng = random.SystemRandom()
    cases = [
        ([rng.randint(3, 47) for _ in range(4)], [rng.randint(3, 47) for _ in range(4)]),
        ([rng.randint(5, 25), rng.randint(30, 60), rng.randint(2, 15), rng.randint(16, 35)],
         [rng.randint(25, 55), rng.randint(2, 14), rng.randint(18, 40), rng.randint(4, 17)]),
        ([rng.randint(40, 70), rng.randint(2, 12), rng.randint(13, 28), rng.randint(5, 20)],
         [rng.randint(3, 16), rng.randint(25, 50), rng.randint(6, 22), rng.randint(30, 60)]),
    ]

    try:
        # Exercise both the submitted executable and a fresh build of the submitted source.
        for program in (EXECUTABLE, rebuilt):
            for case_id, (counts1, counts2) in enumerate(cases):
                run_case(program, counts1, counts2, rng, case_id)
    finally:
        with open(SEQ1, "w") as f:
            f.write(original_seq1)
        with open(SEQ2, "w") as f:
            f.write(original_seq2)

    # Run the demanded executable on the original files; a prewritten result is insufficient.
    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        [EXECUTABLE], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert completed.returncode == 0, f"Executable failed on original inputs: {completed.stderr}"

    seq1_vals, seq2_vals, db_val, k_val = parse_result(strict=True)
    for actual, expected in zip(seq1_vals, expected_seq1):
        assert math.isclose(actual, expected, abs_tol=TOLERANCE)
    for actual, expected in zip(seq2_vals, expected_seq2):
        assert math.isclose(actual, expected, abs_tol=TOLERANCE)
    assert math.isclose(db_val, 0.092010, abs_tol=TOLERANCE)
    assert math.isclose(k_val, 0.045981, abs_tol=TOLERANCE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
