#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tarfile


def test_executable_exists():
    executable_path = "/home/user/src/analyze"
    assert os.path.isfile(executable_path), f"Executable {executable_path} does not exist. Did you compile the C program?"
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Executable {executable_path} is not a compiled native binary."


def test_executable_runs_on_original_dataset():
    results_path = "/home/user/artifacts/results.csv"
    if os.path.exists(results_path):
        os.remove(results_path)
    proc = subprocess.run(
        ["/home/user/src/analyze"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 0, f"analyze failed with exit code {proc.returncode}: {proc.stderr}"
    assert os.path.isfile(results_path), "Running analyze did not generate results.csv."


def test_results_csv_exists_and_correct():
    results_path = "/home/user/artifacts/results.csv"
    assert os.path.isfile(results_path), f"File {results_path} does not exist. Did you run the C program?"

    with open(results_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "EXP_101,0.7000",
        "EXP_102,0.2857",
        "EXP_103,0.9167",
        "EXP_104,0.5000"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in results.csv, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in results.csv is incorrect. Expected '{expected}', got '{actual}'."


def test_fixed_source_and_installed_executable_generalize():
    source_path = "/home/user/src/analyze.c"
    installed_path = "/home/user/src/analyze"
    compiled_path = "/tmp/analyze_from_submitted_source"
    data_path = "/home/user/experiment_data.txt"
    results_path = "/home/user/artifacts/results.csv"

    assert os.path.isfile(source_path), f"Source file {source_path} does not exist."
    compile_proc = subprocess.run(
        ["gcc", "-std=c11", "-O2", source_path, "-o", compiled_path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_proc.returncode == 0, f"Submitted analyze.c does not compile: {compile_proc.stderr}"

    rows = []
    expected = []
    used_ids = set()
    for _ in range(7):
        while True:
            exp_id = "VERIFY_" + secrets.token_hex(6).upper()
            if exp_id not in used_ids:
                used_ids.add(exp_id)
                break

        # Avoid values extremely close to a decimal rounding tie so both
        # float and double implementations of the specified formula agree.
        while True:
            total = 1 + secrets.randbelow(30)
            successes = secrets.randbelow(total + 1)
            posterior = (successes + 1) / (total + 2)
            scaled_fraction = (posterior * 10000) % 1
            if abs(scaled_fraction - 0.5) > 0.05:
                break

        outcomes = ["S"] * successes + ["F"] * (total - successes)
        secrets.SystemRandom().shuffle(outcomes)
        rows.append(exp_id + " " + " ".join(outcomes))
        expected.append(f"{exp_id},{posterior:.4f}")

    generated_data = ("\n".join(rows) + "\n").encode("utf-8")
    with open(data_path, "rb") as f:
        original_data = f.read()
    with open(results_path, "rb") as f:
        original_results = f.read()

    def run_and_check(program):
        with open(data_path, "wb") as f:
            f.write(generated_data)
        if os.path.exists(results_path):
            os.remove(results_path)
        proc = subprocess.run([program], capture_output=True, text=True, timeout=10)
        assert proc.returncode == 0, f"{program} failed on verifier-generated input: {proc.stderr}"
        assert os.path.isfile(results_path), f"{program} did not generate results.csv."
        with open(results_path, "r") as f:
            actual = f.read().splitlines()
        assert actual == expected, f"{program} produced incorrect output for verifier-generated experiment data. Expected {expected}, got {actual}."

    try:
        run_and_check(installed_path)
        run_and_check(compiled_path)
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)
        with open(results_path, "wb") as f:
            f.write(original_results)


def test_tarball_exists_and_contains_artifacts():
    tarball_path = "/home/user/artifacts.tar.gz"
    assert os.path.isfile(tarball_path), f"Tarball {tarball_path} does not exist."
    assert tarfile.is_tarfile(tarball_path), f"File {tarball_path} is not a valid tar archive."

    with tarfile.open(tarball_path, "r:gz") as tar:
        members = tar.getnames()

        # Check that artifacts directory is at the root of the tarball
        # It should contain something like 'artifacts/results.csv'
        has_results_csv = any(m.endswith("artifacts/results.csv") for m in members)
        assert has_results_csv, "Tarball does not contain 'artifacts/results.csv'. Make sure the 'artifacts' directory is at the root of the tarball."

        # Verify the contents of the results.csv inside the tarball
        for member in tar.getmembers():
            if member.name.endswith("artifacts/results.csv"):
                f = tar.extractfile(member)
                assert f is not None, "Could not extract results.csv from tarball."
                content = f.read().decode('utf-8').splitlines()
                lines = [line.strip() for line in content if line.strip()]

                expected_lines = [
                    "EXP_101,0.7000",
                    "EXP_102,0.2857",
                    "EXP_103,0.9167",
                    "EXP_104,0.5000"
                ]
                assert lines == expected_lines, "The results.csv inside the tarball does not match the expected output."
                break
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
