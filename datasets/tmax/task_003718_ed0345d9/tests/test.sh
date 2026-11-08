#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/analyze.sh"
EXPECTED_ORIGINAL = (
    "Control Mean: 149.00\n"
    "Treatment Mean: 203.63\n"
    "Absolute Difference: 54.63"
)


def run_script(dataset_path):
    completed = subprocess.run(
        ["/bin/bash", SCRIPT_PATH, dataset_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"analyze.sh exited with status {completed.returncode}.\n"
        f"stderr:\n{completed.stderr}"
    )
    return completed.stdout.strip()


def test_analyze_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_results_file_content():
    results_path = "/home/user/results.txt"

    assert os.path.exists(results_path), f"Results file {results_path} does not exist."
    assert os.path.isfile(results_path), f"{results_path} is not a file."

    with open(results_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == EXPECTED_ORIGINAL, (
        f"Content of {results_path} does not match expected output.\n"
        f"Expected:\n{EXPECTED_ORIGINAL}\n"
        f"Got:\n{actual_content}"
    )


def test_script_output_for_supplied_dataset():
    actual = run_script("/home/user/dataset.csv")
    assert actual == EXPECTED_ORIGINAL, (
        "analyze.sh did not produce the required output for dataset.csv.\n"
        f"Expected:\n{EXPECTED_ORIGINAL}\nGot:\n{actual}"
    )


def cents_text(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def test_script_reads_first_argument_and_computes_unseen_inputs():
    rng = secrets.SystemRandom()

    for case_number in range(2):
        control_mean = rng.randrange(12000, 45000)
        treatment_mean = rng.randrange(12000, 45000)
        while treatment_mean == control_mean:
            treatment_mean = rng.randrange(12000, 45000)

        control_delta = rng.randrange(101, 1000)
        treatment_delta = rng.randrange(101, 1000)

        rows = [
            ["1", "Control", cents_text(control_mean - control_delta)],
            ["2", "Control", cents_text(control_mean)],
            ["3", "Control", cents_text(control_mean + control_delta)],
            ["4", "Treatment", cents_text(treatment_mean - treatment_delta)],
            ["5", "Treatment", cents_text(treatment_mean)],
            ["6", "Treatment", cents_text(treatment_mean + treatment_delta)],
            ["7", "Control", ""],
            ["8", "Control", "-25.50"],
            ["9", "Control", "0"],
            ["10", "Treatment", "NaN"],
            ["11", "Treatment", f"{rng.randrange(50000, 90000)}.99junk"],
            ["12", "Unknown", cents_text(rng.randrange(50000, 90000))],
            ["13", "control", cents_text(rng.randrange(50000, 90000))],
        ]
        rng.shuffle(rows)

        expected = (
            f"Control Mean: {cents_text(control_mean)}\n"
            f"Treatment Mean: {cents_text(treatment_mean)}\n"
            f"Absolute Difference: {cents_text(abs(control_mean - treatment_mean))}"
        )

        with tempfile.TemporaryDirectory(prefix=f"analyze_case_{case_number}_") as tmpdir:
            dataset_path = os.path.join(tmpdir, secrets.token_hex(8) + ".csv")
            with open(dataset_path, "w") as dataset:
                dataset.write("transaction_id,cohort,amount\n")
                for row in rows:
                    dataset.write(",".join(row) + "\n")

            actual = run_script(dataset_path)
            assert actual == expected, (
                "analyze.sh failed on an unseen dataset supplied as its first argument.\n"
                f"Expected:\n{expected}\nGot:\n{actual}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
