#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess


def test_recovered_log():
    log_path = "/home/user/recovered.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. You must extract the valid transactions."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "SUCCESS: id=101, metric=2.5",
        "SUCCESS: id=102, metric=5.0",
        "SUCCESS: id=103, metric=8.1",
        "SUCCESS: id=104, metric=1.0"
    ]
    assert lines == expected, f"Content of {log_path} is incorrect. Expected exactly {len(expected)} specific SUCCESS lines, but got: {lines}"


def test_crash_csv():
    crash_path = "/home/user/crash.csv"
    assert os.path.isfile(crash_path), f"{crash_path} does not exist. You must identify the crashing line."

    with open(crash_path, "r") as f:
        content = f.read().strip()

    expected = "5,10,2.0"
    assert content == expected, f"Content of {crash_path} is incorrect. Expected '{expected}', got '{content}'."


def test_cargo_run_success():
    project_dir = "/home/user/fin-model"
    assert os.path.isdir(project_dir), f"{project_dir} does not exist."

    cargo_toml_path = os.path.join(project_dir, "Cargo.toml")
    assert os.path.isfile(cargo_toml_path), f"{cargo_toml_path} is missing."
    with open(cargo_toml_path, "r") as f:
        cargo_content = f.read()
    assert 'edition = "2025"' not in cargo_content, "Cargo.toml still contains the invalid edition '2025'."

    result = subprocess.run(
        ["cargo", "run"],
        cwd=project_dir,
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, (
        f"cargo run failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}\n"
        "Ensure that the Cargo.toml is valid and the precision loss bug in main.rs is fixed."
    )

    assert "Result is not finite" not in result.stderr, "Panic 'Result is not finite' still occurs. The math bug is not fully fixed."


def test_recovered_log_is_derived_from_journal():
    journal_path = "/home/user/fin-model/transactions.journal"
    recovered_path = "/home/user/recovered.log"
    with open(journal_path, "rb") as f:
        expected = [line for line in f.read().splitlines() if line.startswith(b"SUCCESS:")]
    with open(recovered_path, "rb") as f:
        actual = [line for line in f.read().splitlines() if line]
    assert actual == expected, "recovered.log does not exactly contain the SUCCESS lines present in transactions.journal"


def _rust_integer_division(a, b):
    quotient = abs(a) // abs(b)
    return -quotient if (a < 0) != (b < 0) else quotient


def test_crash_line_is_derived_from_inputs():
    inputs_path = "/home/user/fin-model/inputs.csv"
    candidates = []
    with open(inputs_path, "r") as f:
        for raw_line in f:
            line = raw_line.rstrip("\r\n")
            parts = line.split(",")
            if len(parts) != 3:
                continue
            a, b = int(parts[0]), int(parts[1])
            c = float(parts[2])
            if b == 0 or (_rust_integer_division(a, b) == 0 and math.isfinite(c)):
                candidates.append(line)
    assert len(candidates) == 1, f"Expected one input that triggers the original division bug, found {candidates}"
    with open("/home/user/crash.csv", "r") as f:
        actual = f.read().strip()
    assert actual == candidates[0], "crash.csv is not the line that triggers the original integer-division panic"


def test_program_processes_runtime_generated_inputs_with_float_division():
    project_dir = "/home/user/fin-model"
    inputs_path = os.path.join(project_dir, "inputs.csv")
    with open(inputs_path, "rb") as f:
        original_inputs = f.read()

    rng = secrets.SystemRandom()
    cases = []
    for _ in range(4):
        b = rng.randrange(20, 200)
        a = rng.randrange(1, b)
        c = rng.randrange(1, 10000) / 13.0
        cases.append((a, b, c))
    for _ in range(4):
        b = rng.randrange(3, 80)
        multiplier = rng.randrange(1, 8)
        a = b * multiplier + rng.randrange(1, b)
        c = rng.randrange(1, 10000) / 17.0
        cases.append((a, b, c))

    encoded_lines = [f"{a},{b},{format(c, '.17g')}" for a, b, c in cases]
    parsed_cases = []
    for line in encoded_lines:
        a_text, b_text, c_text = line.split(",")
        parsed_cases.append((int(a_text), int(b_text), float(c_text)))

    try:
        with open(inputs_path, "w") as f:
            f.write("\n".join(encoded_lines) + "\n")

        result = subprocess.run(
            ["cargo", "run"],
            cwd=project_dir,
            capture_output=True,
            text=True,
            timeout=120
        )
    finally:
        with open(inputs_path, "wb") as f:
            f.write(original_inputs)

    assert result.returncode == 0, (
        f"cargo run failed on verifier-generated inputs.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert "Result is not finite" not in result.stderr

    output_values = []
    for line in result.stdout.splitlines():
        prefix = "Processed metric:"
        if line.startswith(prefix):
            try:
                output_values.append(float(line[len(prefix):].strip()))
            except ValueError as exc:
                raise AssertionError(f"Invalid metric output line: {line!r}") from exc

    assert len(output_values) == len(parsed_cases), (
        f"Program did not process every generated input exactly once; expected {len(parsed_cases)} metrics, got {output_values}"
    )
    expected_values = [c / (float(a) / float(b)) for a, b, c in parsed_cases]
    for index, (actual, expected) in enumerate(zip(output_values, expected_values)):
        assert math.isfinite(actual), f"Metric {index} is not finite: {actual}"
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), (
            f"Metric {index} used incorrect division: expected {expected}, got {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
