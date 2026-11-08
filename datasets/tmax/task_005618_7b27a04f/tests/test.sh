#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import secrets
import subprocess
from collections import defaultdict

PROJECT = "/home/user/etl_pipeline"
CARGO_TOML = os.path.join(PROJECT, "Cargo.toml")
RAW_LOGS = "/home/user/raw_logs.txt"
OUTPUT_CSV = "/home/user/data_warehouse/aggregated_stats.csv"
CARGO = "/usr/local/cargo/bin/cargo"
DECIMAL_2 = re.compile(r"^[+-]?\d+\.\d{2}$")


def run_pipeline():
    subprocess.run(
        [CARGO, "build", "--manifest-path", CARGO_TOML],
        cwd=PROJECT,
        check=True,
        timeout=120,
    )
    if os.path.exists(OUTPUT_CSV):
        os.remove(OUTPUT_CSV)
    subprocess.run(
        [CARGO, "run", "--quiet", "--manifest-path", CARGO_TOML],
        cwd=PROJECT,
        check=True,
        timeout=120,
    )
    assert os.path.isfile(OUTPUT_CSV), "The executed Rust pipeline did not generate the output CSV."


def expected_from_raw(path):
    data = defaultdict(list)
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(" - ")
            if len(parts) >= 4:
                endpoint = parts[1]
                status = parts[2]
                if status == "500":
                    continue
                time_ms = float(parts[3].replace("ms", ""))
                data[endpoint].append(time_ms)

    expected_stats = {}
    for endpoint, times in data.items():
        n = len(times)
        mean = sum(times) / n
        if n > 1:
            variance = sum((x - mean) ** 2 for x in times) / (n - 1)
            std_dev = math.sqrt(variance)
            margin = 1.96 * (std_dev / math.sqrt(n))
        else:
            margin = 0.0
        expected_stats[endpoint] = {
            "count": n,
            "mean": round(mean, 2),
            "ci_lower": round(mean - margin, 2),
            "ci_upper": round(mean + margin, 2),
        }
    return expected_stats


def validate_csv(output_csv, expected_stats):
    with open(output_csv, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, f"The CSV file {output_csv} is empty."

        expected_header = ["endpoint", "count", "mean", "ci_lower", "ci_upper"]
        assert header == expected_header, f"Incorrect CSV header. Expected {expected_header}, got {header}"
        rows = list(reader)

    endpoints_in_csv = [row[0] for row in rows]
    assert endpoints_in_csv == sorted(endpoints_in_csv), "CSV rows are not sorted alphabetically by the 'endpoint' column."
    assert len(rows) == len(expected_stats), f"Expected {len(expected_stats)} rows in the CSV, but found {len(rows)}."

    for row in rows:
        assert len(row) == 5, f"Expected 5 columns in row, got {len(row)}: {row}"
        endpoint = row[0]
        assert DECIMAL_2.fullmatch(row[2]), f"Mean must have exactly two decimal places: {row[2]}"
        assert DECIMAL_2.fullmatch(row[3]), f"ci_lower must have exactly two decimal places: {row[3]}"
        assert DECIMAL_2.fullmatch(row[4]), f"ci_upper must have exactly two decimal places: {row[4]}"

        count = int(row[1])
        mean = float(row[2])
        ci_lower = float(row[3])
        ci_upper = float(row[4])

        assert endpoint in expected_stats, f"Unexpected endpoint found in CSV: {endpoint}"
        exp = expected_stats[endpoint]
        assert count == exp["count"], f"For endpoint {endpoint}: expected count {exp['count']}, got {count}"
        assert math.isclose(mean, exp["mean"], abs_tol=0.01), f"For endpoint {endpoint}: expected mean {exp['mean']}, got {mean}"
        assert math.isclose(ci_lower, exp["ci_lower"], abs_tol=0.01), f"For endpoint {endpoint}: expected ci_lower {exp['ci_lower']}, got {ci_lower}"
        assert math.isclose(ci_upper, exp["ci_upper"], abs_tol=0.01), f"For endpoint {endpoint}: expected ci_upper {exp['ci_upper']}, got {ci_upper}"


def test_00_build_and_execute_rust_pipeline():
    assert os.path.isfile(CARGO_TOML), f"Rust project manifest not found at {CARGO_TOML}. Did you create the project?"
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "Rust source file src/main.rs was not found."
    run_pipeline()


def test_rust_project_exists():
    cargo_toml = "/home/user/etl_pipeline/Cargo.toml"
    assert os.path.exists(cargo_toml), f"Rust project manifest not found at {cargo_toml}. Did you create the project?"


def test_output_file_exists():
    output_csv = "/home/user/data_warehouse/aggregated_stats.csv"
    assert os.path.exists(output_csv), f"Output CSV not found at {output_csv}. Did you create the data_warehouse directory and write the file?"


def test_csv_contents():
    expected_stats = expected_from_raw(RAW_LOGS)
    validate_csv(OUTPUT_CSV, expected_stats)


def test_pipeline_processes_fresh_input():
    with open(RAW_LOGS, "rb") as f:
        original = f.read()

    token = secrets.token_hex(5)
    alpha = f"/audit/{token}/alpha"
    beta = f"/audit/{token}/beta"
    single = f"/audit/{token}/single"
    dynamic_log = "\n".join([
        f"[2026-01-02 03:04:05] 10.1.0.1 - {beta} - 200 - 81.3ms",
        f"[2026-01-02 03:04:06] 10.1.0.2 - {alpha} - 201 - 14.7ms",
        f"[2026-01-02 03:04:07] 10.1.0.3 - {beta} - 500 - 999.9ms",
        f"[2026-01-02 03:04:08] 10.1.0.4 - {alpha} - 200 - 29.2ms",
        f"[2026-01-02 03:04:09] 10.1.0.5 - {beta} - 204 - 103.8ms",
        f"[2026-01-02 03:04:10] 10.1.0.6 - {alpha} - 200 - 46.1ms",
        f"[2026-01-02 03:04:11] 10.1.0.7 - {single} - 200 - 7.4ms",
    ]) + "\n"

    try:
        with open(RAW_LOGS, "w") as f:
            f.write(dynamic_log)
        run_pipeline()
        validate_csv(OUTPUT_CSV, expected_from_raw(RAW_LOGS))
    finally:
        with open(RAW_LOGS, "wb") as f:
            f.write(original)
        subprocess.run(
            [CARGO, "run", "--quiet", "--manifest-path", CARGO_TOML],
            cwd=PROJECT,
            check=False,
            timeout=120,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
