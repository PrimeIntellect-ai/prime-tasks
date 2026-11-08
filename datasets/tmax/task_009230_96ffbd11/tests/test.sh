#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import stat
import subprocess
from pathlib import Path

HOME = Path("/home/user")
ETL = HOME / "etl.sh"
READINGS = HOME / "readings.csv"
PRIORS = HOME / "priors.csv"
OUTPUT = HOME / "anomalies.txt"


def run_etl():
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()

    result = subprocess.run(
        [str(ETL)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{ETL} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT.exists(), f"File {OUTPUT} is missing. The script did not generate it."


def read_output():
    with OUTPUT.open("r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_original_output():
    path = "/home/user/anomalies.txt"
    assert os.path.exists(path), f"File {path} is missing. The script did not generate it."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {path}, but found {len(lines)}."

    # Expected calculations (can be recomputed or directly checked since the input is fixed)
    # s5: (1 - exp(-3.50)) * 0.9 = 0.872822
    # s3: (1 - exp(-2.99)) * 0.7 = 0.664815
    # s6: (1 - exp(-1.20)) * 0.95 = 0.663865
    expected = [
        ("s5", 0.872822),
        ("s3", 0.664815),
        ("s6", 0.663865),
    ]

    for i, (line, (exp_sensor, exp_prob)) in enumerate(zip(lines, expected)):
        parts = line.split()
        assert len(parts) == 2, (
            f"Line {i+1} is malformed: '{line}'. "
            "Expected format 'sensor_id probability'."
        )

        sensor, prob_str = parts
        assert sensor == exp_sensor, (
            f"Line {i+1}: expected sensor '{exp_sensor}', got '{sensor}'."
        )

        try:
            prob = float(prob_str)
        except ValueError:
            assert False, f"Line {i+1}: probability '{prob_str}' is not a valid float."

        assert math.isclose(prob, exp_prob, abs_tol=1e-5), (
            f"Line {i+1}: expected probability ~{exp_prob:.6f}, got {prob:.6f}."
        )


def assert_dynamic_output(expected):
    lines = read_output()
    assert len(lines) == 3, f"Expected exactly 3 dynamic results, found {len(lines)}: {lines}"

    parsed = []
    for i, line in enumerate(lines):
        parts = line.split()
        assert len(parts) == 2, (
            f"Dynamic output line {i+1} is malformed: '{line}'. "
            "Expected 'sensor_id probability'."
        )
        sensor, probability = parts
        try:
            probability = float(probability)
        except ValueError:
            assert False, f"Dynamic output probability '{probability}' is not a valid float."
        assert math.isfinite(probability), f"Probability on line {i+1} is not finite."
        parsed.append((sensor, probability))

    assert [sensor for sensor, _ in parsed] == [sensor for sensor, _ in expected], (
        f"Expected dynamically computed top-3 sensors "
        f"{[sensor for sensor, _ in expected]}, got {[sensor for sensor, _ in parsed]}."
    )
    assert all(parsed[i][1] > parsed[i + 1][1] for i in range(len(parsed) - 1)), (
        "Dynamic results are not in strictly descending posterior order."
    )

    for i, ((sensor, actual), (_, wanted)) in enumerate(zip(parsed, expected)):
        assert math.isclose(actual, wanted, rel_tol=0.0, abs_tol=1e-5), (
            f"Dynamic line {i+1} ({sensor}): expected posterior {wanted:.6f}, "
            f"got {actual:.6f}."
        )


def test_script_executes_and_computes_pipeline():
    assert ETL.exists(), f"Required script {ETL} is missing."
    mode = ETL.stat().st_mode
    assert stat.S_ISREG(mode), f"{ETL} must be a regular file."
    assert os.access(ETL, os.X_OK), f"{ETL} is not executable."

    tracked = [READINGS, PRIORS, OUTPUT]
    backups = {
        path: (path.exists(), path.read_bytes() if path.exists() else b"")
        for path in tracked
    }

    try:
        # Execute the submitted artifact on the original inputs, then retain all
        # assertions from the original verifier against the generated file.
        run_etl()
        assert_original_output()

        # Exercise the same artifact on fresh sensor IDs and values so a fixed
        # anomalies.txt or a script that prints the known three rows cannot pass.
        prefix = secrets.token_hex(6)
        rows = [
            (f"{prefix}_a", 4.20, 0.92),
            (f"{prefix}_b", 2.40, 0.88),
            (f"{prefix}_c", 1.80, 0.90),
            (f"{prefix}_d", 3.10, 0.72),
            (f"{prefix}_e", 0.40, 0.99),
            (f"{prefix}_f", 5.00, 0.48),
            (f"{prefix}_g", 1.10, 0.80),
        ]
        reading_rows = [(sensor, value) for sensor, value, _ in rows]
        reading_rows.append((f"{prefix}_reading_only", 9.0))
        prior_rows = [(sensor, prior) for sensor, _, prior in rows]
        prior_rows.append((f"{prefix}_prior_only", 0.99))
        random.SystemRandom().shuffle(reading_rows)
        random.SystemRandom().shuffle(prior_rows)

        READINGS.write_text("".join(f"{sensor},{value:.8f}\n" for sensor, value in reading_rows))
        PRIORS.write_text("".join(f"{sensor},{prior:.8f}\n" for sensor, prior in prior_rows))

        expected = sorted(
            (
                (sensor, (1.0 - math.exp(-value)) * prior)
                for sensor, value, prior in rows
                if (1.0 - math.exp(-value)) * prior > 0.5
            ),
            key=lambda item: item[1],
            reverse=True,
        )[:3]

        run_etl()
        assert_dynamic_output(expected)
    finally:
        for path, (existed, contents) in backups.items():
            if existed:
                path.write_bytes(contents)
            elif path.exists() or path.is_symlink():
                path.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
