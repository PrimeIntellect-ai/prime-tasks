#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import subprocess

SCRIPT = "/home/user/analyze_mutations.sh"
DATA = "/home/user/mutations.tsv"
REPORT = "/home/user/report.txt"

REPORT_RE = re.compile(
    r"\ABase Rate B: (-?\d+\.\d{4})\n"
    r"Bootstrap 2\.5%: (-?\d+\.\d{4})\n"
    r"Bootstrap 97\.5%: (-?\d+\.\d{4})\n"
    r"Divergence Gen: (\d+)\n?\Z"
)


def run_script():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        ["bash", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"analyze_mutations.sh exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), "The executed script did not create /home/user/report.txt."
    with open(REPORT, "r") as f:
        content = f.read()
    match = REPORT_RE.fullmatch(content)
    assert match, "report.txt is not in the required four-line format with four decimal places."
    return content, tuple(map(float, match.group(1, 2, 3))) + (int(match.group(4)),)


def ols(rows):
    xs = [x for x, _ in rows]
    zs = [math.log(y) for _, y in rows]
    mx = sum(xs) / len(xs)
    mz = sum(zs) / len(zs)
    denom = sum((x - mx) ** 2 for x in xs)
    assert denom > 0
    b = sum((x - mx) * (z - mz) for x, z in zip(xs, zs)) / denom
    intercept = mz - b * mx
    return intercept, b


def expected_values(rows):
    intercept, base_b = ols(rows)
    threshold = (math.log(100000.0) - intercept) / base_b
    divergence = math.floor(threshold) + 1
    while math.exp(intercept + base_b * (divergence - 1)) > 100000.0:
        divergence -= 1
    while math.exp(intercept + base_b * divergence) <= 100000.0:
        divergence += 1

    rng = random.Random(42)
    boot = []
    n = len(rows)
    for _ in range(1000):
        sample = [rows[rng.randrange(n)] for _ in range(n)]
        try:
            _, b = ols(sample)
        except AssertionError:
            continue
        boot.append(b)
    boot.sort()
    assert len(boot) >= 975
    return base_b, boot[24], boot[974], divergence


def write_rows(rows):
    with open(DATA, "w") as f:
        f.write("Generation\tMutations\n")
        for x, y in rows:
            f.write(f"{x}\t{y:.8f}\n")


def make_rows(a, b, residuals):
    return [(i, a * math.exp(b * i + residuals[i - 1])) for i in range(1, len(residuals) + 1)]


def check_derived_case(rows):
    write_rows(rows)
    _, actual = run_script()
    base_b, low, high, divergence = actual
    expected_b, expected_low, expected_high, expected_divergence = expected_values(rows)

    assert abs(base_b - expected_b) <= 0.00011, (
        f"Base Rate B was {base_b}, expected {expected_b:.4f} for the supplied data."
    )
    assert divergence == expected_divergence, (
        f"Divergence Gen was {divergence}, expected {expected_divergence} for the supplied data."
    )
    # Different compliant seeded PRNG implementations need not draw identical samples,
    # so compare against independently calculated 1000-resample percentiles with a
    # small allowance for Monte Carlo/PRNG variation.
    assert abs(low - expected_low) <= 0.012, (
        f"Bootstrap 2.5% was {low}, inconsistent with a 1000-row-resample CI near {expected_low:.4f}."
    )
    assert abs(high - expected_high) <= 0.012, (
        f"Bootstrap 97.5% was {high}, inconsistent with a 1000-row-resample CI near {expected_high:.4f}."
    )
    assert low <= high, "Bootstrap 2.5% should be less than or equal to Bootstrap 97.5%."


def test_script_executes_and_computes_results():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is not a regular file."
    with open(SCRIPT, "r") as f:
        content = f.read()
    # Preserve the original Bash-loop assertion.
    assert re.search(r"\b(for|while)\b", content), "The script must contain a Bash loop (for or while)."
    syntax = subprocess.run(["bash", "-n", SCRIPT], text=True, capture_output=True)
    assert syntax.returncode == 0, f"Script is not valid Bash syntax: {syntax.stderr}"

    with open(DATA, "rb") as f:
        original_data = f.read()

    try:
        # Execute against the original required dataset and preserve all original checks.
        original_content, original = run_script()
        base_rate, boot_low, boot_high, div_gen = original
        assert abs(base_rate - 0.3950) < 1e-4, f"Expected Base Rate B to be 0.3950, got {base_rate}."
        assert div_gen == 25, f"Expected Divergence Gen to be 25, got {div_gen}."
        assert 0.2 < boot_low < 0.5, f"Bootstrap 2.5% value {boot_low} is outside expected range."
        assert 0.3 < boot_high < 0.6, f"Bootstrap 97.5% value {boot_high} is outside expected range."
        assert boot_low <= boot_high, "Bootstrap 2.5% should be less than or equal to Bootstrap 97.5%."

        # A second execution must reproduce the report when seed 42 is used.
        repeated_content, _ = run_script()
        assert repeated_content == original_content, "Repeated execution is not deterministic."

        # Exercise the artifact on data unknown when the agent ran. Expected answers
        # are derived here, preventing a prewritten fixed report from passing.
        check_derived_case(make_rows(
            7.0, 0.27,
            [0.18, -0.12, 0.07, -0.16, 0.11, -0.04, 0.15, -0.09, 0.03, -0.14, 0.10, -0.02],
        ))
        check_derived_case(make_rows(
            80.0, 0.11,
            [-0.20, 0.13, -0.08, 0.17, -0.03, 0.09, -0.15, 0.05, 0.14, -0.11, 0.02, -0.06, 0.12, -0.04],
        ))
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        # Leave the required report corresponding to the original dataset.
        subprocess.run(["bash", SCRIPT], cwd="/home/user", timeout=180)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
