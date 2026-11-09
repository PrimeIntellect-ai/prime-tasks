#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp /home/user/data/sensors.csv "$backup_dir/sensors.csv"
if [ -f /home/user/sensor_analysis/correlation.txt ]; then
    cp /home/user/sensor_analysis/correlation.txt "$backup_dir/correlation.txt"
    had_output=1
else
    had_output=0
fi
cleanup() {
    cp "$backup_dir/sensors.csv" /home/user/data/sensors.csv
    if [ "$had_output" = "1" ]; then
        cp "$backup_dir/correlation.txt" /home/user/sensor_analysis/correlation.txt
    else
        rm -f /home/user/sensor_analysis/correlation.txt
    fi
    rm -rf "$backup_dir"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import subprocess

PROJECT = "/home/user/sensor_analysis"
DATA_FILE = "/home/user/data/sensors.csv"
OUTPUT_FILE = os.path.join(PROJECT, "correlation.txt")


def test_rust_project_exists():
    """Check if the Rust project was created."""
    cargo_toml = "/home/user/sensor_analysis/Cargo.toml"
    assert os.path.isfile(cargo_toml), f"Rust project file {cargo_toml} does not exist. Did you create the Cargo project?"


def test_correlation_file_exists():
    """Check if the output file exists."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."


def test_correlation_value():
    """Check if the correlation value is correct."""
    X = [20.5, 22.1, 19.8, 23.0, 24.5, 18.0, 19.2, 25.1]
    Y = [45.0, 48.2, 43.5, 52.0, 55.5, 40.0, 42.1, 58.0]

    n = len(X)
    sum_x = sum(X)
    sum_y = sum(Y)
    sum_x_sq = sum(x**2 for x in X)
    sum_y_sq = sum(y**2 for y in Y)
    sum_xy = sum(x*y for x, y in zip(X, Y))

    numerator = n * sum_xy - sum_x * sum_y
    denominator = math.sqrt((n * sum_x_sq - sum_x**2) * (n * sum_y_sq - sum_y**2))
    r = numerator / denominator
    expected_value = f"{r:.4f}"

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == expected_value, f"Expected correlation value '{expected_value}', but got '{content}'."


def test_project_uses_required_rust_schema_and_crates():
    result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps", "--offline"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Cargo project metadata failed:\n{result.stderr}"
    metadata = json.loads(result.stdout)
    packages = metadata.get("packages", [])
    assert packages, "Cargo metadata contains no package"

    package = next((p for p in packages if p.get("name") == "sensor_analysis"), packages[0])
    dependency_names = {d.get("name") for d in package.get("dependencies", [])}
    assert "csv" in dependency_names, "Cargo.toml must depend on the csv crate"
    assert "serde" in dependency_names, "Cargo.toml must depend on the serde crate"

    forbidden = {"statrs", "ndarray-stats", "linregress", "smartcore", "polars"}
    assert not (dependency_names & forbidden), "Pearson correlation must not use an external statistics crate"

    rust_files = []
    for root, _, files in os.walk(os.path.join(PROJECT, "src")):
        for name in files:
            if name.endswith(".rs"):
                rust_files.append(os.path.join(root, name))
    assert rust_files, "The Cargo project has no Rust source files under src/"

    source = "\n".join(open(path, encoding="utf-8").read() for path in rust_files)
    assert re.search(r"\bcsv\b", source), "Rust source does not use the csv crate"
    assert re.search(r"\bserde\b", source) and re.search(r"\bDeserialize\b", source), \
        "Rust source must deserialize records with serde"
    assert re.search(r"\bid\s*:\s*u32\b", source), "The record schema must define id as u32"
    assert re.search(r"\btemperature\s*:\s*f64\b", source), "The record schema must define temperature as f64"
    assert re.search(r"\bhumidity\s*:\s*f64\b", source), "The record schema must define humidity as f64"
    assert re.search(r"\.sqrt\s*\(", source), "Rust source must directly implement the Pearson calculation"


def pearson_text(xs, ys):
    n = len(xs)
    sum_x = sum(xs)
    sum_y = sum(ys)
    sum_x_sq = sum(x * x for x in xs)
    sum_y_sq = sum(y * y for y in ys)
    sum_xy = sum(x * y for x, y in zip(xs, ys))
    numerator = n * sum_xy - sum_x * sum_y
    denominator = math.sqrt((n * sum_x_sq - sum_x * sum_x) * (n * sum_y_sq - sum_y * sum_y))
    return f"{numerator / denominator:.4f}"


def test_program_is_executed_and_filters_malformed_rows():
    rng = secrets.SystemRandom()

    for trial in range(2):
        valid = []
        for i in range(9):
            temperature = round(10.0 + rng.randrange(0, 25000) / 1000.0, 3)
            humidity = round(25.0 + temperature * 0.83 + rng.randrange(-3500, 3501) / 1000.0, 3)
            valid.append((1000 + trial * 100 + i, temperature, humidity))

        rows = [f"{row_id},{temperature:.3f},{humidity:.3f}" for row_id, temperature, humidity in valid]
        rows.extend([
            "not-an-id,17.500,44.000",
            "-1,18.500,45.000",
            "4294967296,19.500,46.000",
            "77,broken,47.000",
            "78,20.500,invalid",
            "79,21.500",
        ])
        rng.shuffle(rows)
        with open(DATA_FILE, "w", encoding="utf-8", newline="") as f:
            f.write("id,temperature,humidity\n")
            f.write("\n".join(rows) + "\n")

        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        result = subprocess.run(
            ["cargo", "run", "--quiet", "--offline"],
            cwd=PROJECT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=90,
        )
        assert result.returncode == 0, f"Cargo program failed on test data:\n{result.stderr}"
        assert os.path.isfile(OUTPUT_FILE), "Running the Rust program did not create correlation.txt"

        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            raw = f.read()
        assert re.fullmatch(r"-?\d+\.\d{4}\n?", raw), \
            f"correlation.txt must contain exactly one number with four decimal places, got {raw!r}"

        expected = pearson_text(
            [temperature for _, temperature, _ in valid],
            [humidity for _, _, humidity in valid],
        )
        assert raw.strip() == expected, \
            f"Expected correlation {expected} after filtering malformed rows, got {raw.strip()!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
