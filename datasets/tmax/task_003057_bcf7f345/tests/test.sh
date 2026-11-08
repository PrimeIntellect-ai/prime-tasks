#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

EXPERIMENTS = Path("/home/user/experiments.csv")
RESULTS = Path("/home/user/results.csv")
HEADER = "exp_id,posterior_alpha,posterior_beta,expected_value"


def expected_lines_for(experiments_file):
    stats = defaultdict(lambda: {
        "successes": 0,
        "failures": 0,
        "prior_alpha": 0,
        "prior_beta": 0,
    })

    with open(experiments_file, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or len(row) < 10:
                continue
            exp_id = row[0]
            f1, f2, f3 = float(row[1]), float(row[2]), float(row[3])
            w1, w2, w3 = float(row[4]), float(row[5]), float(row[6])
            target = float(row[7])
            prior_alpha = int(row[8])
            prior_beta = int(row[9])

            stats[exp_id]["prior_alpha"] = prior_alpha
            stats[exp_id]["prior_beta"] = prior_beta
            prediction = (f1 * w1) + (f2 * w2) + (f3 * w3)
            if abs(prediction - target) < 0.1:
                stats[exp_id]["successes"] += 1
            else:
                stats[exp_id]["failures"] += 1

    expected = [HEADER]
    for exp_id in sorted(stats):
        post_alpha = stats[exp_id]["prior_alpha"] + stats[exp_id]["successes"]
        post_beta = stats[exp_id]["prior_beta"] + stats[exp_id]["failures"]
        ev = post_alpha / (post_alpha + post_beta)
        expected.append(f"{exp_id},{post_alpha},{post_beta},{ev:.4f}")
    return expected


def assert_results_match(experiments_file, results_file):
    expected_lines = expected_lines_for(experiments_file)
    with open(results_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected the header and {len(expected_lines) - 1} data rows in results.csv, "
        f"but found {len(actual_lines)} non-empty lines."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines), 1):
        assert actual == expected, (
            f"Line {i} mismatch. Expected '{expected}', but got '{actual}'."
        )


def test_01_results_csv_exists():
    assert RESULTS.exists(), (
        "/home/user/results.csv does not exist. The C program may not have run "
        "or failed to create the output file."
    )
    assert RESULTS.is_file(), "/home/user/results.csv is not a file."


def test_02_results_csv_content():
    assert EXPERIMENTS.exists(), f"{EXPERIMENTS} is missing."
    assert_results_match(EXPERIMENTS, RESULTS)


def test_03_c_pipeline_rebuilds_and_processes_new_input():
    sources = sorted(Path("/home/user").rglob("*.c"))
    assert sources, "No C source file was found under /home/user."

    main_sources = []
    for source in sources:
        text = source.read_text(errors="ignore")
        if re.search(r"\bmain\s*\(", text):
            main_sources.append(source)
    assert main_sources, "The submitted C sources do not define a main function."

    binary = Path(tempfile.gettempdir()) / f"verifier_analyze_{os.getpid()}"
    compile_cmd = ["gcc", "-std=c11", "-O2", *map(str, sources), "-lm", "-o", str(binary)]
    compiled = subprocess.run(
        compile_cmd, cwd="/home/user", text=True, capture_output=True, timeout=30
    )
    assert compiled.returncode == 0, (
        "The submitted C pipeline could not be compiled:\n"
        + compiled.stdout + compiled.stderr
    )
    assert binary.is_file() and os.access(binary, os.X_OK), (
        "Compiling the submitted C sources did not produce an executable."
    )

    original_experiments = EXPERIMENTS.read_bytes()
    original_results = RESULTS.read_bytes() if RESULTS.exists() else None

    rng = random.SystemRandom()
    rows = []
    priors = {}
    for exp_id in ["Q", "A", "M"]:
        priors[exp_id] = (rng.randint(1, 8), rng.randint(1, 8))
        for trial in range(rng.randint(3, 6)):
            features = [rng.randint(-20, 20) / 10.0 for _ in range(3)]
            weights = [rng.randint(-15, 15) / 10.0 for _ in range(3)]
            prediction = sum(f * w for f, w in zip(features, weights))
            success = rng.choice([True, False])
            target = prediction if success else prediction + rng.choice([-0.25, 0.25])
            alpha, beta = priors[exp_id]
            rows.append([
                exp_id,
                *(f"{value:.1f}" for value in features),
                *(f"{value:.1f}" for value in weights),
                f"{target:.6f}",
                str(alpha),
                str(beta),
            ])

    # Exercise the strict threshold explicitly: |prediction-target| == 0.1 is failure.
    alpha, beta = priors["A"]
    rows.append(["A", "0.0", "0.0", "0.0", "1.0", "1.0", "1.0", "0.1", str(alpha), str(beta)])
    rng.shuffle(rows)

    try:
        with open(EXPERIMENTS, "w", newline="") as f:
            csv.writer(f, lineterminator="\n").writerows(rows)
        if RESULTS.exists() or RESULTS.is_symlink():
            RESULTS.unlink()

        executed = subprocess.run(
            [str(binary)], cwd="/home/user", text=True, capture_output=True, timeout=30
        )
        assert executed.returncode == 0, (
            "The freshly compiled C pipeline failed when executed:\n"
            + executed.stdout + executed.stderr
        )
        assert RESULTS.exists() and RESULTS.is_file(), (
            "The freshly compiled C pipeline did not create /home/user/results.csv."
        )
        assert_results_match(EXPERIMENTS, RESULTS)
    finally:
        EXPERIMENTS.write_bytes(original_experiments)
        if original_results is None:
            if RESULTS.exists() or RESULTS.is_symlink():
                RESULTS.unlink()
        else:
            RESULTS.write_bytes(original_results)
        if binary.exists():
            binary.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
