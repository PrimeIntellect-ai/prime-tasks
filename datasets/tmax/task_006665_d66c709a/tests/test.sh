#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import math
import re
import subprocess
import pytest

REF = "ATGCGTACGTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG"
BASES = "ACGT"

state = 42

def next_rand():
    global state
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF
    return state

def align_score(p):
    max_score = 0
    for i in range(len(REF) - 9):
        score = sum(1 for a, b in zip(p, REF[i:i+10]))
        if score > max_score:
            max_score = score
    return max_score

def gc_score(p):
    g = sum(1 for c in p if c in 'GC')
    return -1.0 * (g - 5)**2

def total_score(p):
    return align_score(p) + gc_score(p)

def get_ideal_dist():
    dist = []
    for k in range(11):
        dist.append(math.comb(10, k) / 1024.0)
    return dist

def run_ground_truth():
    global state
    state = 42

    current_p = list("AAAAAAAAAA")
    current_score = total_score(current_p)

    gc_counts = [0] * 11

    N = 500000
    for _ in range(N):
        idx = next_rand() % 10
        base_idx = next_rand() % 4
        new_c = BASES[base_idx]

        old_c = current_p[idx]
        current_p[idx] = new_c
        new_score = total_score(current_p)

        # Avoid overflow by capping alpha
        if new_score >= current_score:
            alpha = 1.0
        else:
            alpha = math.exp(new_score - current_score)

        u = (next_rand() % 1000000) / 1000000.0

        if u < alpha:
            current_score = new_score
        else:
            current_p[idx] = old_c # revert

        g = sum(1 for c in current_p if c in 'GC')
        gc_counts[g] += 1

    ideal = get_ideal_dist()
    tvd = 0.5 * sum(abs(gc_counts[k]/float(N) - ideal[k]) for k in range(11))
    return tvd

def test_source_code_exists():
    assert os.path.isfile("/home/user/generate_primers.c"), "/home/user/generate_primers.c does not exist."

def test_program_compiles_and_runs():
    source = "/home/user/generate_primers.c"
    executable = "/tmp/generate_primers_agent"
    output = "/home/user/mcmc_results.txt"

    if os.path.exists(executable):
        os.remove(executable)

    compile_result = subprocess.run(
        ["/usr/bin/gcc", "-O2", "-std=c11", source, "-lm", "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"
    assert os.path.isfile(executable), "Compilation did not produce an executable."

    # Remove any precomputed result so the submitted program must create it.
    if os.path.lexists(output):
        os.remove(output)

    run_result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert run_result.returncode == 0, f"Program failed:\n{run_result.stderr}"
    assert os.path.isfile(output), "The executed program did not create /home/user/mcmc_results.txt."

def test_output_file_exists():
    assert os.path.isfile("/home/user/mcmc_results.txt"), "/home/user/mcmc_results.txt does not exist."

def test_output_format():
    with open("/home/user/mcmc_results.txt", "r") as f:
        content = f.read()
    assert re.fullmatch(r"[0-9]+\.[0-9]{6}\n", content), \
        "Output must contain exactly one TVD line formatted to six decimal places."

def test_mcmc_results_correctness():
    output_file = "/home/user/mcmc_results.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} not found."

    with open(output_file, "r") as f:
        content = f.read().strip()

    try:
        agent_tvd = float(content)
    except ValueError:
        pytest.fail(f"Could not parse TVD from output file. Content was: {content}")

    truth_tvd = run_ground_truth()

    assert abs(agent_tvd - truth_tvd) < 1e-4, f"Expected TVD approx {truth_tvd:.6f}, got {agent_tvd:.6f}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
