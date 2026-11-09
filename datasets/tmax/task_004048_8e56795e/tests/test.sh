#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess

SOURCE = "/home/user/validate.rs"
INPUT = "/home/user/predictions.csv"
OUTPUT = "/home/user/output.txt"
BINARY = "/tmp/validate_submission"

CANONICAL = """id,model_score,is_correct
1,0.75,1
2,0.72,0
3,0.81,1
4,0.79,1
5,0.65,0
6,0.70,1
7,0.799,0
8,0.80,0
9,0.73,1
10,0.77,1
11,0.74,1
"""


def write_input(content):
    with open(INPUT, "w") as f:
        f.write(content)


def run_and_check(expected):
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [BINARY], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT), f"Expected output file not found at {OUTPUT}."
    assert os.path.isfile(OUTPUT), f"Expected {OUTPUT} to be a file."

    with open(OUTPUT, "r") as f:
        content = f.read().strip()

    assert content == expected, (
        f"The content of {OUTPUT} is incorrect.\n"
        f"Expected: '{expected}'\nGot: '{content}'"
    )


def test_program_compiles_runs_and_computes_results():
    assert os.path.lexists(SOURCE), f"Expected Rust source not found at {SOURCE}."
    mode = os.lstat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"Expected {SOURCE} to be a regular source file."

    compile_result = subprocess.run(
        ["rustc", SOURCE, "-o", BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE}.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )

    try:
        # Preserve the original verifier's exact assertion, but obtain the output
        # by executing the submitted program against the canonical input.
        write_input(CANONICAL)
        run_and_check("N=8,K=6,PosteriorMean=0.7000")

        # Explicitly exercise both interval boundaries.
        boundary_case = """id,model_score,is_correct
1,0.699999,1
2,0.70,1
3,0.7000,0
4,0.75,1
5,0.799999,0
6,0.80,1
7,0.95,1
"""
        write_input(boundary_case)
        run_and_check("N=4,K=2,PosteriorMean=0.5000")

        # Use runtime-generated datasets so a constant output cannot pass.
        rng = random.Random(secrets.randbits(128))
        in_scores = ["0.70", "0.701", "0.725", "0.749", "0.775", "0.7999"]
        out_scores = ["0.0", "0.42", "0.6999", "0.80", "0.8001", "0.99"]

        for _ in range(3):
            n = rng.choice(list(range(9, 50, 2)))
            k = rng.randint(0, n)
            correctness = [1] * k + [0] * (n - k)
            rng.shuffle(correctness)

            rows = []
            for value in correctness:
                rows.append([rng.choice(in_scores), value])
            for _ in range(rng.randint(4, 10)):
                rows.append([rng.choice(out_scores), rng.randint(0, 1)])
            rng.shuffle(rows)

            csv_lines = ["id,model_score,is_correct"]
            for row_id, (score, correct) in enumerate(rows, 1):
                csv_lines.append(f"{row_id},{score},{correct}")
            write_input("\n".join(csv_lines) + "\n")

            expected_mean = (1 + k) / (n + 2)
            expected = f"N={n},K={k},PosteriorMean={expected_mean:.4f}"
            run_and_check(expected)
    finally:
        write_input(CANONICAL)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
