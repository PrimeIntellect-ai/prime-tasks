#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/analyze.sh"
OUTPUT_PATH = "/home/user/best_candidates.txt"
EXPERIMENTS = "/home/user/experiments"


def pearson_corr(x, y):
    n = len(x)
    sum_x = sum(x)
    sum_y = sum(y)
    sum_x_sq = sum(v ** 2 for v in x)
    sum_y_sq = sum(v ** 2 for v in y)
    sum_xy = sum(a * b for a, b in zip(x, y))
    num = n * sum_xy - sum_x * sum_y
    den = math.sqrt((n * sum_x_sq - sum_x ** 2) *
                    (n * sum_y_sq - sum_y ** 2))
    return 0.0 if den == 0 else num / den


def read_even_epochs(filepath):
    values = []
    with open(filepath, "r") as f:
        next(f)
        for line in f:
            if not line.strip():
                continue
            epoch, loss = line.strip().split(",")
            if int(epoch) % 2 == 0:
                values.append(float(loss))
    return values


def expected_lines():
    baseline_path = os.path.join(EXPERIMENTS, "baseline.csv")
    assert os.path.isfile(baseline_path), "baseline.csv missing."
    base_loss = read_even_epochs(baseline_path)

    correlations = []
    for i in range(1, 6):
        cand_file = f"cand_{i}.csv"
        cand_path = os.path.join(EXPERIMENTS, cand_file)
        if os.path.isfile(cand_path):
            cand_loss = read_even_epochs(cand_path)
            correlations.append((cand_file, pearson_corr(base_loss, cand_loss)))

    correlations.sort(key=lambda x: x[1], reverse=True)
    return [f"{name} {corr:.4f}" for name, corr in correlations[:2]]


def assert_output_matches(expected):
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert len(actual) == 2, (
        f"Expected exactly 2 lines in {OUTPUT_PATH}, found {len(actual)}."
    )
    for i in range(2):
        assert actual[i] == expected[i], (
            f"Line {i + 1} mismatch in {OUTPUT_PATH}. "
            f"Expected '{expected[i]}', got '{actual[i]}'."
        )


def run_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f"analyze.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def write_csv(path, even_values, odd_values):
    with open(path, "w") as f:
        f.write("epoch,loss\n")
        for epoch in range(1, 101):
            index = (epoch - 1) // 2
            value = even_values[index] if epoch % 2 == 0 else odd_values[index]
            f.write(f"{epoch},{value:.4f}\n")


def test_analyze_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r", errors="replace") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.match(r"^#!.*(?:/bash|env\s+bash)(?:\s|$)", first_line), \
        "analyze.sh must be a Bash script."

    # The requested computation must be implemented with Bash/Unix tools, not
    # delegated to another programming-language interpreter.
    body_lines = []
    for line in source.splitlines()[1:]:
        body_lines.append(line.split("#", 1)[0])
    body = "\n".join(body_lines)
    forbidden = re.compile(
        r"(?<![A-Za-z0-9_])(?:python[0-9.]*|pypy[0-9.]*|perl|ruby|node|nodejs|"
        r"php|lua|Rscript)(?![A-Za-z0-9_])|(?:^|[\s;&|()])R(?:\s|$)",
        re.MULTILINE,
    )
    assert not forbidden.search(body), \
        "analyze.sh must use Bash and standard Unix tools, not another language."


def test_best_candidates_output():
    # Preserve the original final-state assertion.
    assert_output_matches(expected_lines())


def test_script_generates_correct_output_on_original_inputs():
    expected = expected_lines()
    run_script()
    assert_output_matches(expected)


def test_script_recomputes_from_even_epochs_on_unseen_inputs():
    old_output = None
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            old_output = f.read()

    with tempfile.TemporaryDirectory() as tempdir:
        backup = os.path.join(tempdir, "experiments")
        shutil.copytree(EXPERIMENTS, backup)
        try:
            rng = random.SystemRandom()
            base_even = [rng.uniform(-2.0, 2.0) for _ in range(50)]
            base_odd = [rng.uniform(-1000.0, 1000.0) for _ in range(50)]

            cand_even = {
                1: [0.4 * x + rng.uniform(-0.5, 0.5) for x in base_even],
                2: [-x + rng.uniform(-0.05, 0.05) for x in base_even],
                3: [rng.uniform(-2.0, 2.0) for _ in range(50)],
                4: [1.1 * x + rng.uniform(-0.01, 0.01) for x in base_even],
                5: [0.7 * x + rng.uniform(-0.12, 0.12) for x in base_even],
            }
            # Odd epochs deliberately make cand_2 appear best if a submission
            # fails to perform the required systematic sampling.
            cand_odd = {
                1: [rng.uniform(-1000.0, 1000.0) for _ in range(50)],
                2: list(base_odd),
                3: [-x for x in base_odd],
                4: [rng.uniform(-1000.0, 1000.0) for _ in range(50)],
                5: [rng.uniform(-1000.0, 1000.0) for _ in range(50)],
            }

            write_csv(os.path.join(EXPERIMENTS, "baseline.csv"),
                      base_even, base_odd)
            for i in range(1, 6):
                write_csv(os.path.join(EXPERIMENTS, f"cand_{i}.csv"),
                          cand_even[i], cand_odd[i])

            expected = expected_lines()
            run_script()
            assert_output_matches(expected)
        finally:
            shutil.rmtree(EXPERIMENTS)
            shutil.copytree(backup, EXPERIMENTS)
            if old_output is None:
                if os.path.exists(OUTPUT_PATH):
                    os.remove(OUTPUT_PATH)
            else:
                with open(OUTPUT_PATH, "wb") as f:
                    f.write(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
