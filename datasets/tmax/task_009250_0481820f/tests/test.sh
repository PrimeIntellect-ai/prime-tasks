#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

SCRIPT = "/home/user/prepare_data.sh"
INPUT = "/home/user/input_data.csv"
OUTPUT = "/home/user/training_data.csv"
EXPECTED_ORIGINAL = (
    "sim_id,optimal_k\n"
    "1,0.01\n"
    "2,0.04\n"
    "3,0.00\n"
    "4,0.02"
)
ORIGINAL_INPUT = (
    "sim_id,v0,target_v10\n"
    "1,0.0,30.0\n"
    "2,10.0,15.0\n"
    "3,0.0,50.0\n"
    "4,5.0,22.0\n"
)


def assert_exact_output(expected_content):
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist. Did you run your script?"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()

    expected_lines = expected_content.splitlines()
    actual_lines = content.splitlines()
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {OUTPUT}, but found {len(actual_lines)}."
    )
    for i, (expected_line, actual_line) in enumerate(zip(expected_lines, actual_lines)):
        assert actual_line == expected_line, (
            f"Mismatch at line {i + 1} in {OUTPUT}. "
            f"Expected '{expected_line}', got '{actual_line}'."
        )


def euler(v0, k):
    v = v0
    for _ in range(100):
        v += 0.1 * (9.8 - k * v * v)
    return v


def expected_k(v0, target):
    errors = []
    for n in range(101):
        k = n / 100.0
        errors.append((abs(euler(v0, k) - target), n))
    return min(errors)[1]


def run_script():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Running {SCRIPT} did not create {OUTPUT}."


def check_generated_output(rows):
    with open(OUTPUT, "r") as f:
        lines = f.read().strip().splitlines()

    assert lines and lines[0] == "sim_id,optimal_k", "Incorrect output header."
    assert len(lines) == len(rows) + 1, "Output must contain exactly one row per input row."

    for line, (sim_id, v0, target) in zip(lines[1:], rows):
        match = re.fullmatch(r"([^,]+),(\d\.\d{2})", line)
        assert match, f"Malformed output row or k not formatted to exactly two decimals: {line!r}"
        assert match.group(1) == sim_id, "Simulation IDs or row order were not preserved."
        expected = expected_k(v0, target)
        assert match.group(2) == f"{expected / 100:.2f}", (
            f"Wrong optimal k for sim_id {sim_id}: expected {expected / 100:.2f}, "
            f"got {match.group(2)}."
        )


def test_prepare_data_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    with open(SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").strip()
    assert re.fullmatch(r"#!(?:/bin/bash|/usr/bin/bash|/usr/bin/env +bash)", first_line), (
        f"{SCRIPT} must be an executable Bash script."
    )


def test_training_data_exists_and_correct():
    assert_exact_output(EXPECTED_ORIGINAL)


def test_script_performs_processing_on_unseen_inputs():
    old_input = open(INPUT, "rb").read()
    old_output = open(OUTPUT, "rb").read() if os.path.exists(OUTPUT) else None
    rng = secrets.SystemRandom()

    try:
        # Re-running on the supplied input must itself regenerate the required file.
        with open(INPUT, "w") as f:
            f.write(ORIGINAL_INPUT)
        run_script()
        assert_exact_output(EXPECTED_ORIGINAL)

        # Exercise unseen data. Targets are generated with the required 100 Euler
        # steps, while expected labels are independently selected over 0.00..1.00.
        for batch in range(2):
            rows = []
            used_k = set()
            for index in range(4):
                while True:
                    k_hundredths = rng.randrange(0, 101)
                    if k_hundredths not in used_k:
                        used_k.add(k_hundredths)
                        break
                v0 = rng.randrange(0, 801) / 100.0
                target = euler(v0, k_hundredths / 100.0)
                sim_id = str(rng.randrange(10000, 99999))
                rows.append((sim_id, v0, float(f"{target:.12f}")))

            with open(INPUT, "w") as f:
                f.write("sim_id,v0,target_v10\n")
                for sim_id, v0, target in rows:
                    f.write(f"{sim_id},{v0:.2f},{target:.12f}\n")

            run_script()
            check_generated_output(rows)
    finally:
        with open(INPUT, "wb") as f:
            f.write(old_input)
        if old_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
