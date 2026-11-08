#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import subprocess

SOURCE = "/home/user/compare.cpp"
EXECUTABLE = "/tmp/compare_submission"
OUT_PATH = "/home/user/kl_divergence.txt"
REF_PATH = "/home/user/reference.txt"
OPT_PATH = "/home/user/optimized.txt"


def run_submission():
    if os.path.exists(OUT_PATH):
        os.remove(OUT_PATH)
    result = subprocess.run(
        [EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(OUT_PATH), f"Program did not produce {OUT_PATH}"


def expected_kl(ref, opt):
    min_val = min(min(ref), min(opt))
    max_val = max(max(ref), max(opt))
    W = (max_val - min_val) / 100.0

    P_counts = [0] * 100
    Q_counts = [0] * 100

    for v in ref:
        idx = int(math.floor((v - min_val) / W))
        if idx >= 100:
            idx = 99
        P_counts[idx] += 1

    for v in opt:
        idx = int(math.floor((v - min_val) / W))
        if idx >= 100:
            idx = 99
        Q_counts[idx] += 1

    P = [c / len(ref) for c in P_counts]
    Q = [c / len(opt) for c in Q_counts]
    P_adj = [p + 1e-9 for p in P]
    Q_adj = [q + 1e-9 for q in Q]
    kl = sum(p * math.log(p / q) for p, q in zip(P_adj, Q_adj))
    return f"{kl:.6f}"


def write_values(path, values):
    with open(path, "w") as f:
        for value in values:
            f.write(f"{value:.17g}\n")


def test_00_cpp_source_compiles_and_runs():
    assert os.path.isfile(SOURCE), f"C++ source file missing: {SOURCE}"
    assert os.path.getsize(SOURCE) > 0, f"C++ source file is empty: {SOURCE}"

    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-x", "c++", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"compare.cpp failed to compile as C++: {result.stderr}"
    assert os.path.isfile(EXECUTABLE), "Compilation did not produce an executable"
    run_submission()


def test_kl_divergence_output():
    out_path = "/home/user/kl_divergence.txt"
    assert os.path.isfile(out_path), f"Output file missing: {out_path}"

    ref_path = "/home/user/reference.txt"
    opt_path = "/home/user/optimized.txt"

    assert os.path.isfile(ref_path), f"Input file missing: {ref_path}"
    assert os.path.isfile(opt_path), f"Input file missing: {opt_path}"

    with open(ref_path, 'r') as f:
        ref = [float(x) for x in f if x.strip()]

    with open(opt_path, 'r') as f:
        opt = [float(x) for x in f if x.strip()]

    min_val = min(min(ref), min(opt))
    max_val = max(max(ref), max(opt))
    W = (max_val - min_val) / 100.0

    P_counts = [0] * 100
    Q_counts = [0] * 100

    for v in ref:
        idx = int(math.floor((v - min_val) / W))
        if idx >= 100: 
            idx = 99
        P_counts[idx] += 1

    for v in opt:
        idx = int(math.floor((v - min_val) / W))
        if idx >= 100: 
            idx = 99
        Q_counts[idx] += 1

    P = [c / len(ref) for c in P_counts]
    Q = [c / len(opt) for c in Q_counts]

    P_adj = [p + 1e-9 for p in P]
    Q_adj = [q + 1e-9 for q in Q]

    kl = sum(p * math.log(p / q) for p, q in zip(P_adj, Q_adj))
    expected_output = f"{kl:.6f}"

    with open(out_path, 'r') as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, f"Expected KL divergence {expected_output}, but got {actual_output}"


def test_program_on_fresh_inputs():
    with open(REF_PATH, "rb") as f:
        original_ref = f.read()
    with open(OPT_PATH, "rb") as f:
        original_opt = f.read()

    rng = random.Random(secrets.randbits(128))
    cases = []
    for ref_size, opt_size in [(257, 311), (503, 419)]:
        center = rng.uniform(-20.0, 20.0)
        ref = [rng.gauss(center, 0.4 + rng.random() * 2.0) for _ in range(ref_size)]
        opt = [rng.gauss(center + rng.uniform(-1.0, 1.0), 0.5 + rng.random() * 2.5) for _ in range(opt_size)]
        ref.extend([center - 12.5, center + 14.75])
        opt.extend([center - 9.25, center + 17.5])
        cases.append((ref, opt))

    try:
        for ref, opt in cases:
            write_values(REF_PATH, ref)
            write_values(OPT_PATH, opt)
            expected = expected_kl(ref, opt)
            run_submission()
            with open(OUT_PATH, "r") as f:
                actual = f.read().strip()
            assert actual == expected, (
                f"Program produced {actual!r} on fresh inputs; expected {expected!r}"
            )
    finally:
        with open(REF_PATH, "wb") as f:
            f.write(original_ref)
        with open(OPT_PATH, "wb") as f:
            f.write(original_opt)
        try:
            run_submission()
        finally:
            with open(REF_PATH, "wb") as f:
                f.write(original_ref)
            with open(OPT_PATH, "wb") as f:
                f.write(original_opt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
