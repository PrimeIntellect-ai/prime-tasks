#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess

DATA_PATH = "/home/user/perf_data.csv"
SOURCE_PATH = "/home/user/optimizer.cpp"
WEIGHTS_PATH = "/home/user/weights.txt"
VIS_PATH = "/home/user/visualize.sh"
BINARY_PATH = "/tmp/optimizer_submission"


def run_checked(command, timeout=15):
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout)


def test_00_optimizer_exists_compiles_reads_csv_and_produces_weights():
    assert os.path.isfile(SOURCE_PATH), f"Missing file: {SOURCE_PATH}"
    assert not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} must be a regular source file"
    assert stat.S_ISREG(os.stat(SOURCE_PATH).st_mode), f"{SOURCE_PATH} is not a regular file"
    assert os.path.getsize(SOURCE_PATH) > 0, f"{SOURCE_PATH} is empty"

    compile_result = run_checked(["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", BINARY_PATH], timeout=30)
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE_PATH}. Stderr: {compile_result.stderr}"
    )

    with open(DATA_PATH, "rb") as f:
        original_csv = f.read()

    rng = secrets.SystemRandom()
    try:
        for _ in range(3):
            # A diagonally dominant design matrix guarantees independent columns.
            a, b, c = (rng.randint(10, 20) for _ in range(3))
            rows = [
                (a, 1, 1),
                (1, b, 1),
                (1, 1, c),
                (rng.randint(3, 15), rng.randint(3, 15), rng.randint(3, 15)),
                (rng.randint(3, 15), rng.randint(3, 15), rng.randint(3, 15)),
            ]
            coeff_cents = [rng.randint(75, 450) for _ in range(3)]

            lines = ["CPU,Mem,IO,Latency"]
            for cpu, mem, io in rows:
                latency_cents = cpu * coeff_cents[0] + mem * coeff_cents[1] + io * coeff_cents[2]
                lines.append(f"{cpu},{mem},{io},{latency_cents / 100:.2f}")
            with open(DATA_PATH, "w") as f:
                f.write("\n".join(lines) + "\n")

            if os.path.exists(WEIGHTS_PATH):
                os.remove(WEIGHTS_PATH)
            result = run_checked([BINARY_PATH])
            assert result.returncode == 0, (
                f"Compiled optimizer failed with return code {result.returncode}. Stderr: {result.stderr}"
            )
            assert os.path.isfile(WEIGHTS_PATH), "Compiled optimizer did not create weights.txt"
            with open(WEIGHTS_PATH) as f:
                actual = f.read().strip()
            expected = "CPU={:.2f} MEM={:.2f} IO={:.2f}".format(
                coeff_cents[0] / 100, coeff_cents[1] / 100, coeff_cents[2] / 100
            )
            assert actual == expected, (
                f"Optimizer did not derive weights from the current CSV. Expected '{expected}', got '{actual}'."
            )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_csv)
        if os.path.exists(WEIGHTS_PATH):
            os.remove(WEIGHTS_PATH)
        restore_result = run_checked([BINARY_PATH])
        assert restore_result.returncode == 0, (
            f"Optimizer failed on the reference dataset. Stderr: {restore_result.stderr}"
        )


def test_weights_file():
    """Verify that weights.txt exists and has the correct exact content."""
    file_path = "/home/user/weights.txt"
    assert os.path.isfile(file_path), f"Missing file: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = "CPU=2.50 MEM=1.20 IO=4.00"
    assert content == expected_content, f"Content of {file_path} is incorrect. Expected '{expected_content}', got '{content}'."


def test_visualize_script_exists_and_executable():
    """Verify that visualize.sh exists and is executable."""
    file_path = "/home/user/visualize.sh"
    assert os.path.isfile(file_path), f"Missing file: {file_path}"
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."
    assert not os.path.islink(file_path), f"{file_path} must be a regular bash script"
    with open(file_path, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, f"{file_path} must have a bash shebang"
    syntax = run_checked(["bash", "-n", file_path])
    assert syntax.returncode == 0, f"Invalid bash syntax in {file_path}: {syntax.stderr}"


def test_visualize_script_output():
    """Verify the output of visualize.sh matches the expected format."""
    file_path = "/home/user/visualize.sh"

    result = run_checked([file_path])
    assert result.returncode == 0, f"Script {file_path} failed with return code {result.returncode}. Stderr: {result.stderr}"

    output = result.stdout.strip()

    expected_lines = [
        "Row 1: Pred=69.00 Actual: ******",
        "Row 2: Pred=145.00 Actual: **************",
        "Row 3: Pred=138.00 Actual: *************",
        "Row 4: Pred=231.00 Actual: ***********************",
        "Row 5: Pred=210.00 Actual: *********************"
    ]

    output_lines = [line.strip() for line in output.split("\n") if line.strip()]

    for i, expected_line in enumerate(expected_lines):
        assert i < len(output_lines), f"Missing output line. Expected: '{expected_line}'"
        assert output_lines[i] == expected_line, f"Output line {i+1} is incorrect. Expected '{expected_line}', got '{output_lines[i]}'."


def test_visualize_reads_current_csv_and_weights():
    with open(DATA_PATH, "rb") as f:
        original_csv = f.read()
    with open(WEIGHTS_PATH, "rb") as f:
        original_weights = f.read()

    rng = secrets.SystemRandom()
    coeff_cents = [rng.randint(80, 425) for _ in range(3)]
    rows = [
        (rng.randint(1, 25), rng.randint(1, 25), rng.randint(1, 25), rng.randint(21, 89)),
        (rng.randint(1, 25), rng.randint(1, 25), rng.randint(1, 25), rng.randint(90, 179)),
        (rng.randint(1, 25), rng.randint(1, 25), rng.randint(1, 25), rng.randint(180, 269)),
    ]

    try:
        with open(WEIGHTS_PATH, "w") as f:
            f.write("CPU={:.2f} MEM={:.2f} IO={:.2f}\n".format(
                coeff_cents[0] / 100, coeff_cents[1] / 100, coeff_cents[2] / 100
            ))
        with open(DATA_PATH, "w") as f:
            f.write("CPU,Mem,IO,Latency\n")
            for cpu, mem, io, actual in rows:
                f.write(f"{cpu},{mem},{io},{actual}\n")

        result = run_checked([VIS_PATH])
        assert result.returncode == 0, (
            f"Visualization failed on valid changed inputs. Stderr: {result.stderr}"
        )
        actual_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        expected_lines = []
        for index, (cpu, mem, io, actual) in enumerate(rows, start=1):
            predicted_cents = cpu * coeff_cents[0] + mem * coeff_cents[1] + io * coeff_cents[2]
            expected_lines.append(
                f"Row {index}: Pred={predicted_cents / 100:.2f} Actual: " + ("*" * (actual // 10))
            )
        assert actual_lines == expected_lines, (
            "visualize.sh did not calculate its output from the current CSV and weights.txt. "
            f"Expected {expected_lines}, got {actual_lines}."
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_csv)
        with open(WEIGHTS_PATH, "wb") as f:
            f.write(original_weights)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
