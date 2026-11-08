#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile
from decimal import Decimal, ROUND_HALF_UP
from fractions import Fraction

import pytest

SCRIPT_PATH = "/home/user/evaluate.sh"
OUTPUT_PATH = "/home/user/best_model.txt"
ARTIFACTS_PATH = "/home/user/artifacts"


def test_evaluate_script_exists_and_executable():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_best_model_output():
    output_path = OUTPUT_PATH
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, "r") as f:
        content = f.read().strip()

    expected_content = "model_alpha,0.8846"
    assert content == expected_content, f"Expected output '{expected_content}', but got '{content}'"


def expected_output(records):
    rates = {
        name: Fraction(successes + 1, successes + failures + 2)
        for name, (successes, failures) in records.items()
    }
    winner = max(rates, key=rates.get)
    rate = Decimal(rates[winner].numerator) / Decimal(rates[winner].denominator)
    rendered = rate.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
    return f"{winner},{rendered:.4f}"


def install_records(records):
    if os.path.exists(ARTIFACTS_PATH):
        shutil.rmtree(ARTIFACTS_PATH)
    os.makedirs(ARTIFACTS_PATH)

    for name, (successes, failures) in records.items():
        path = os.path.join(ARTIFACTS_PATH, name + ".log")
        with open(path, "w") as f:
            f.writelines(["OUTCOME: 1\n"] * successes)
            f.writelines(["OUTCOME: 0\n"] * failures)


def run_and_check(records):
    install_records(records)
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=15,
    )

    assert os.path.isfile(OUTPUT_PATH), "evaluate.sh did not create best_model.txt"
    with open(OUTPUT_PATH, "r") as f:
        actual = f.read().strip()
    expected = expected_output(records)
    assert actual == expected, f"Expected output '{expected}', but got '{actual}'"


def test_script_executes_bayesian_evaluation_on_new_inputs():
    backup_root = tempfile.mkdtemp(prefix="evaluate-verifier-")
    backup_artifacts = os.path.join(backup_root, "artifacts")
    shutil.copytree(ARTIFACTS_PATH, backup_artifacts)
    with open(OUTPUT_PATH, "rb") as f:
        original_output = f.read()
    original_mode = os.stat(OUTPUT_PATH).st_mode

    try:
        token = secrets.token_hex(5)

        # The small model has the better empirical rate, while the larger model
        # has the better Beta(1,1) posterior mean.
        shrinkage_case = {
            f"small_{token}": (2, 1),
            f"large_{token}": (61, 39),
            f"average_{token}": (10, 10),
        }
        run_and_check(shrinkage_case)

        rng = random.SystemRandom()
        while True:
            random_case = {}
            for index in range(5):
                total = rng.randint(8, 90)
                successes = rng.randint(1, total - 1)
                random_case[f"candidate_{token}_{index}"] = (
                    successes,
                    total - successes,
                )
            rates = [
                Fraction(s + 1, s + f + 2) for s, f in random_case.values()
            ]
            displayed = [
                (Decimal(rate.numerator) / Decimal(rate.denominator)).quantize(
                    Decimal("0.0001"), rounding=ROUND_HALF_UP
                )
                for rate in rates
            ]
            if len(set(rates)) == len(rates) and len(set(displayed)) == len(displayed):
                break
        run_and_check(random_case)
    finally:
        if os.path.exists(ARTIFACTS_PATH):
            shutil.rmtree(ARTIFACTS_PATH)
        shutil.copytree(backup_artifacts, ARTIFACTS_PATH)
        with open(OUTPUT_PATH, "wb") as f:
            f.write(original_output)
        os.chmod(OUTPUT_PATH, original_mode)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
