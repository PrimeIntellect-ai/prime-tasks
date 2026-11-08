#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import pwd
import random
import re
import stat
import subprocess

SOURCE = "/home/user/analyze.c"
SEQUENCES = "/home/user/sequences.txt"
RESULTS = "/home/user/results.txt"
BINARY = "/tmp/analyze_submission"
REFERENCE = "ATGCGTAC"


def demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def parse_results():
    assert os.path.exists(RESULTS), f"File not found: {RESULTS}"
    assert os.path.isfile(RESULTS), f"Path is not a file: {RESULTS}"
    with open(RESULTS, "r") as f:
        content = f.read()

    mcmc_match = re.search(r"MCMC_Lambda_Mean:\s*([0-9.]+)", content)
    ci_lower_match = re.search(r"Bootstrap_CI_Lower:\s*([0-9.]+)", content)
    ci_upper_match = re.search(r"Bootstrap_CI_Upper:\s*([0-9.]+)", content)

    assert mcmc_match, "Results file is missing 'MCMC_Lambda_Mean: <value>'"
    assert ci_lower_match, "Results file is missing 'Bootstrap_CI_Lower: <value>'"
    assert ci_upper_match, "Results file is missing 'Bootstrap_CI_Upper: <value>'"

    values = tuple(float(m.group(1)) for m in
                   (mcmc_match, ci_lower_match, ci_upper_match))
    assert all(math.isfinite(v) for v in values), "Results contain non-finite values"
    return values


def run_submission():
    try:
        os.remove(RESULTS)
    except FileNotFoundError:
        pass
    subprocess.run(
        [BINARY], cwd="/home/user", check=True, timeout=20,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        preexec_fn=demote_to_user,
    )
    return parse_results()


def exact_bootstrap_interval(distances):
    # Exact distribution of the sum of 50 draws from the empirical distribution.
    counts = [distances.count(i) for i in range(9)]
    pmf = [1.0]
    for _ in range(50):
        nxt = [0.0] * (len(pmf) + 8)
        for total, probability in enumerate(pmf):
            for distance, count in enumerate(counts):
                if count:
                    nxt[total + distance] += probability * count / 50.0
        pmf = nxt

    def quantile(q):
        cumulative = 0.0
        for total, probability in enumerate(pmf):
            cumulative += probability
            if cumulative >= q:
                return total / 50.0
        return (len(pmf) - 1) / 50.0

    return quantile(0.025), quantile(0.975)


def sequences_for_distances(distances, rng):
    lines = []
    bases = "ACGT"
    for distance in distances:
        positions = rng.sample(range(8), distance)
        sequence = list(REFERENCE)
        for position in positions:
            alternatives = [b for b in bases if b != sequence[position]]
            sequence[position] = rng.choice(alternatives)
        lines.append("".join(sequence))
    return "\n".join(lines) + "\n"


def main():
    assert os.path.exists(SOURCE), f"File not found: {SOURCE}"
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f"Not a regular C source file: {SOURCE}"
    assert source_stat.st_size > 0, "analyze.c is empty"

    subprocess.run(
        ["gcc", "-O2", "-std=c11", SOURCE, "-lm", "-o", BINARY],
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )

    with open(SEQUENCES, "rb") as f:
        original_sequences = f.read()

    try:
        # Execute the submitted artifact on the required input and retain the
        # original verifier's assertions.
        mcmc_mean, ci_lower, ci_upper = run_submission()
        assert 0.10 <= mcmc_mean <= 0.18, \
            f"MCMC Mean {mcmc_mean} out of bounds (expected ~0.14)."
        assert 0.02 <= ci_lower <= 0.10, \
            f"CI Lower {ci_lower} out of bounds (expected ~0.04)."
        assert 0.20 <= ci_upper <= 0.30, \
            f"CI Upper {ci_upper} out of bounds (expected ~0.26)."

        # Exercise the compiled program on unpredictable valid inputs. Expected
        # posterior means and bootstrap intervals are derived from those inputs.
        rng = random.SystemRandom()
        posterior_offsets = []
        for _ in range(4):
            high = rng.randint(4, 7)
            middle = rng.randint(1, 3)
            weights = [rng.randint(2, 6), rng.randint(3, 8), rng.randint(1, 5)]
            population = [0] * weights[0] + [middle] * weights[1] + [high] * weights[2]
            distances = [rng.choice(population) for _ in range(50)]

            with open(SEQUENCES, "w") as f:
                f.write(sequences_for_distances(distances, rng))

            mcmc, lower, upper = run_submission()
            sample_mean = sum(distances) / 50.0
            # Uniform(0,8) prior gives a truncated Gamma(S+1, rate=50)
            # posterior; generated cases are far enough from 8 that truncation
            # is negligible.
            expected_mcmc = (sum(distances) + 1.0) / 50.0
            expected_lower, expected_upper = exact_bootstrap_interval(distances)

            assert abs(mcmc - expected_mcmc) <= 0.08, \
                f"MCMC result {mcmc} inconsistent with generated data (expected {expected_mcmc:.3f})"
            assert abs(lower - expected_lower) <= 0.16, \
                f"Bootstrap lower bound {lower} inconsistent with generated data (expected {expected_lower:.3f})"
            assert abs(upper - expected_upper) <= 0.16, \
                f"Bootstrap upper bound {upper} inconsistent with generated data (expected {expected_upper:.3f})"
            assert lower <= sample_mean <= upper, \
                "Bootstrap interval does not contain the observed sample mean"
            posterior_offsets.append(mcmc - sample_mean)

        # Distinguish posterior MCMC estimates from simply printing sample means.
        average_offset = sum(posterior_offsets) / len(posterior_offsets)
        assert 0.005 <= average_offset <= 0.040, \
            f"MCMC estimates do not show the posterior offset expected from the stated prior: {average_offset}"
    finally:
        with open(SEQUENCES, "wb") as f:
            f.write(original_sequences)
        # Leave results.txt produced by the program for the instructed dataset.
        run_submission()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
