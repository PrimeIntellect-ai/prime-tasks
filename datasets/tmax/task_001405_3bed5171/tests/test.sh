#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp /home/user/embeddings.csv "$backup_dir/embeddings.csv"
if [ -f /home/user/centroid.csv ]; then
    cp /home/user/centroid.csv "$backup_dir/centroid.csv"
fi

restore_files() {
    cp "$backup_dir/embeddings.csv" /home/user/embeddings.csv
    if [ -f "$backup_dir/centroid.csv" ]; then
        cp "$backup_dir/centroid.csv" /home/user/centroid.csv
    else
        rm -f /home/user/centroid.csv
    fi
    rm -rf "$backup_dir"
}
trap restore_files EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def calculate_expected(input_file):
    sums = [0.0] * 5
    count = 0
    with open(input_file, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 5:
                for i in range(5):
                    sums[i] += float(parts[i])
                count += 1

    assert count > 0, f"No valid data found in {input_file}."
    return ",".join(f"{s / count:.4f}" for s in sums)


def run_and_check(executable_path):
    output_file = "/home/user/centroid.csv"
    if os.path.exists(output_file):
        os.unlink(output_file)

    result = subprocess.run(
        [executable_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable_path} failed with exit code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(output_file), (
        f"{executable_path} did not create {output_file}."
    )

    expected = calculate_expected("/home/user/embeddings.csv")
    with open(output_file, "r") as f:
        actual_raw = f.read()
    assert actual_raw == expected + "\n", (
        f"Centroid output incorrect or improperly formatted. "
        f"Expected: {expected!r} followed by one newline, Actual: {actual_raw!r}"
    )


def write_random_embeddings():
    rng = secrets.SystemRandom()
    with open("/home/user/embeddings.csv", "w") as f:
        for _ in range(1000):
            values = [rng.randint(-10000, 10000) / 10000.0 for _ in range(5)]
            f.write(",".join(f"{value:.4f}" for value in values) + "\n")


def test_aggregate_executable_exists():
    executable_path = "/home/user/aggregate"
    assert os.path.isfile(executable_path), f"Executable {executable_path} not found. Did you compile the C code?"
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Executable {executable_path} is not a compiled ELF binary."


def test_aggregate_c_is_fixed():
    file_path = "/home/user/aggregate.c"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read()

    assert "int sums[5]" not in content, "The bug 'int sums[5]' is still present in aggregate.c."
    assert "double sums" in content or "float sums" in content, "Could not find a floating-point 'sums' array declaration in aggregate.c."


def test_centroid_output_correct():
    input_file = "/home/user/embeddings.csv"
    output_file = "/home/user/centroid.csv"

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing. Did you run the compiled executable?"

    expected_str = calculate_expected(input_file)
    with open(output_file, "r") as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, f"Centroid output incorrect. Expected: '{expected_str}', Actual: '{actual_str}'"


def test_submitted_executable_produces_output_from_input():
    for _ in range(2):
        write_random_embeddings()
        run_and_check("/home/user/aggregate")


def test_submitted_source_compiles_and_produces_output():
    rebuilt = "/tmp/aggregate_rebuilt"
    result = subprocess.run(
        ["gcc", "/home/user/aggregate.c", "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"aggregate.c does not compile with gcc: {result.stderr}"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

    for _ in range(2):
        write_random_embeddings()
        run_and_check(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
