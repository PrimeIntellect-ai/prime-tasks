#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import random
import subprocess
import uuid

SCRIPT_PATH = "/home/user/validate_trace.sh"
THRESHOLD = 1.05


def test_validate_trace_script_exists():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"


def test_clean_traces_accepted():
    script_path = SCRIPT_PATH
    clean_dir = "/app/traces/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))

    assert len(clean_files) > 0, f"No clean traces found in {clean_dir}"

    failed_files = []
    for f in clean_files:
        result = subprocess.run([script_path, f], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(f))

    if failed_files:
        assert False, f"{len(failed_files)} of {len(clean_files)} clean traces rejected (expected to be accepted). Offending files: {', '.join(failed_files)}"


def test_evil_traces_rejected():
    script_path = SCRIPT_PATH
    evil_dir = "/app/traces/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(evil_files) > 0, f"No evil traces found in {evil_dir}"

    failed_files = []
    for f in evil_files:
        result = subprocess.run([script_path, f], capture_output=True)
        if result.returncode == 0:
            failed_files.append(os.path.basename(f))

    if failed_files:
        assert False, f"{len(failed_files)} of {len(evil_files)} evil traces bypassed (expected to be rejected). Offending files: {', '.join(failed_files)}"


def sample_variance(values):
    mean = sum(values) / len(values)
    return sum((x - mean) ** 2 for x in values) / (len(values) - 1)


def reference_rhat(chains):
    n = len(chains[0])
    means = [sum(chain) / n for chain in chains]
    variances = [sample_variance(chain) for chain in chains]
    within = sum(variances) / len(variances)
    if within == 0:
        return math.inf
    between = n * sample_variance(means)
    estimated = ((n - 1) / n) * within + between / n
    return math.sqrt(estimated / within)


def write_trace(path, chains):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["chain", "step", "value"])
        for step in range(len(chains[0])):
            for chain_id, values in enumerate(chains, 1):
                writer.writerow([chain_id, step, format(values[step], ".17g")])


def make_target_rhat_case(rng, n, target):
    # Two chains with equal within-chain variance and a mean separation chosen
    # from the standard Gelman-Rubin formula to produce the requested R-hat.
    scale = rng.uniform(0.03, 8.0)
    offset = rng.uniform(-50.0, 50.0)
    base = [offset + scale * rng.gauss(0, 1) for _ in range(n)]
    within = sample_variance(base)
    separation = math.sqrt(2 * within * (target * target - (n - 1) / n))
    return [base, [x + separation for x in base]]


def test_generated_traces_are_classified_by_computed_rhat(tmp_path):
    # These files have unpredictable neutral paths and varying lengths/scales;
    # their expected answers are independently derived from their contents.
    rng = random.SystemRandom()
    targets = [0.999, 1.01, 1.035, 1.049, 1.051, 1.07, 1.2, 1.8]
    cases = []

    for target in targets:
        n = rng.randint(23, 137)
        chains = make_target_rhat_case(rng, n, target)
        path = tmp_path / (uuid.uuid4().hex + ".csv")
        write_trace(path, chains)
        calculated = reference_rhat(chains)
        expected_exit = 0 if calculated <= THRESHOLD else 1
        cases.append((path, calculated, expected_exit))

    # Explicit zero-variance input must be rejected even though both chains
    # have the same mean.
    constant = rng.uniform(-100, 100)
    singular_chains = [[constant] * 61, [constant] * 61]
    singular_path = tmp_path / (uuid.uuid4().hex + ".csv")
    write_trace(singular_path, singular_chains)
    assert math.isinf(reference_rhat(singular_chains))
    cases.append((singular_path, math.inf, 1))

    rng.shuffle(cases)
    failures = []
    for path, calculated, expected_exit in cases:
        result = subprocess.run(
            [SCRIPT_PATH, str(path)], capture_output=True, text=True, timeout=10
        )
        if result.returncode != expected_exit:
            failures.append(
                f"{path.name}: R-hat={calculated!r}, expected exit "
                f"{expected_exit}, got {result.returncode}; stderr={result.stderr!r}"
            )

    assert not failures, "Generated trace classification failures:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
