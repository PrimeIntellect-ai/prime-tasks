#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess
from pathlib import Path

SCRIPT_PATH = Path("/home/user/analyze.sh")
CSV_PATH = Path("/home/user/integrator.csv")
REPORT_PATH = Path("/home/user/report.txt")


def expected_output(csv_path):
    residuals = []
    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            residuals.append(float(row["residual"]))

    n = len(residuals)
    assert n > 1, "Not enough data to calculate zero-crossing rate."

    zero_crossings = 0
    for i in range(1, n):
        if residuals[i - 1] * residuals[i] < 0:
            zero_crossings += 1

    rate = zero_crossings / (n - 1)
    neg = sum(1 for r in residuals if r < -1.0)
    pos = sum(1 for r in residuals if r > 1.0)
    neu = sum(1 for r in residuals if -1.0 <= r <= 1.0)

    return "\n".join([
        f"Zero-crossing rate: {rate:.4f}",
        f"Negative: {neg}",
        f"Neutral: {neu}",
        f"Positive: {pos}",
    ])


def run_script():
    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stderr:\n{result.stderr}"
    )
    return result.stdout.strip()


def test_analyze_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_report_content():
    assert os.path.isfile(CSV_PATH), f"Input file {CSV_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."

    expected = expected_output(CSV_PATH)
    actual = REPORT_PATH.read_text().strip()
    assert actual == expected, (
        f"Output in {REPORT_PATH} does not match expected output.\n"
        f"Expected:\n{expected}\n\nActual:\n{actual}"
    )


def test_script_produces_report_for_supplied_csv():
    expected = expected_output(CSV_PATH)
    actual = run_script()
    assert actual == expected, (
        f"{SCRIPT_PATH} did not produce the expected report.\n"
        f"Expected:\n{expected}\n\nActual:\n{actual}"
    )


def test_script_recomputes_results_for_unseen_input():
    original_data = CSV_PATH.read_bytes()
    original_mode = stat.S_IMODE(CSV_PATH.stat().st_mode)
    rng = secrets.SystemRandom()

    try:
        for _ in range(2):
            residuals = [-1.0, 1.0, 0.0, -2.0, 2.0]
            choices = [-3.75, -1.25, -0.8, -0.1, 0.0, 0.4, 1.0, 1.4, 4.2]
            residuals.extend(rng.choice(choices) for _ in range(rng.randint(4, 12)))
            rng.shuffle(residuals)

            lines = ["step,time,value,residual"]
            for i, residual in enumerate(residuals, 1):
                lines.append(f"{i},{i / 10:.1f},{rng.randint(-50, 50) / 10:.1f},{residual}")
            CSV_PATH.write_text("\n".join(lines) + "\n")

            expected = expected_output(CSV_PATH)
            actual = run_script()
            assert actual == expected, (
                f"{SCRIPT_PATH} did not recompute the report for a changed CSV.\n"
                f"Expected:\n{expected}\n\nActual:\n{actual}"
            )
    finally:
        CSV_PATH.write_bytes(original_data)
        os.chmod(CSV_PATH, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
