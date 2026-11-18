#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
from collections import defaultdict
from pathlib import Path

PROJECT = Path("/home/user/config_tracker")
CARGO_TOML = PROJECT / "Cargo.toml"
OUTPUT = Path("/home/user/output/config_summary.csv")
V1 = Path("/home/user/data/config_v1.json")
V2 = Path("/home/user/data/config_v2.csv")
V3 = Path("/home/user/data/config_v3.ini")

CARGO_ENV = os.environ.copy()
CARGO_ENV.update({
    "HOME": "/home/user",
    "CARGO_HOME": "/home/user/.cargo",
    "RUSTUP_HOME": "/home/user/.rustup",
})


def run_submission():
    OUTPUT.unlink(missing_ok=True)
    result = subprocess.run(
        ["/home/user/.cargo/bin/cargo", "run", "--quiet", "--manifest-path", str(CARGO_TOML)],
        cwd=str(PROJECT),
        env=CARGO_ENV,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        "The Rust project did not compile and run successfully.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT.exists(), f"Output file {OUTPUT} is missing after running the Rust program."


def read_output():
    with OUTPUT.open("r", newline="", encoding="utf-8") as f:
        return list(csv.reader(f))


def expected_rows(versions):
    histories = defaultdict(list)
    for version in versions:
        for key, value in version.items():
            normalized = key.lower().replace("-", "_")
            histories[normalized].append(str(value))

    rows = [["normalized_key", "num_changes", "first_value", "latest_value"]]
    for key in sorted(histories):
        values = histories[key]
        changes = sum(a != b for a, b in zip(values, values[1:]))
        rows.append([key, str(changes), values[0], values[-1]])
    return rows


def write_fixtures(v1, v2, v3):
    V1.write_text(json.dumps(v1, indent=2) + "\n", encoding="utf-8")
    with V2.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["key", "value"])
        writer.writerows(v2.items())
    with V3.open("w", encoding="utf-8") as f:
        f.write("[default]\n")
        for key, value in v3.items():
            f.write(f"{key}={value}\n")


def test_rust_project_exists():
    cargo_toml_path = "/home/user/config_tracker/Cargo.toml"
    assert os.path.exists(cargo_toml_path), f"Rust project Cargo.toml not found at {cargo_toml_path}. Did you create the cargo project?"
    assert os.path.isfile(cargo_toml_path), f"{cargo_toml_path} is not a regular file."


def test_output_csv_exists_and_correct():
    expected = [
        ["normalized_key", "num_changes", "first_value", "latest_value"],
        ["db_host", "1", "localhost", "127.0.0.1"],
        ["enable_cache", "1", "true", "false"],
        ["log_level", "2", "INFO", "WARN"],
        ["max_connections", "1", "100", "150"],
        ["server_port", "1", "8080", "8081"],
        ["timeout", "0", "30", "30"],
    ]

    run_submission()
    actual = read_output()
    assert len(actual) > 0, f"Output file {OUTPUT} is empty."
    assert actual[0] == expected[0], f"Headers mismatch in {OUTPUT}. Expected {expected[0]}, got {actual[0]}"
    assert actual == expected, f"Data mismatch in {OUTPUT}. Expected {expected}, got {actual}"


def test_program_handles_unseen_multi_format_inputs():
    original_files = {path: path.read_bytes() for path in (V1, V2, V3)}
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None

    try:
        for _ in range(2):
            token = secrets.token_hex(8)
            v1 = {
                f"Service-Port-{token}": f"old_{token}",
                f"Gap-Key-{token}": f"gap_old_{token}",
                f"Old-Only-{token}": f"only_old_{token}",
                f"Stable-{token}": f"same_{token}",
                f"Case-{token}": f"case_one_{token}",
            }
            v2 = {
                f"SERVICE_PORT_{token}": f"middle,{token}",
                f"stable_{token}": f"same_{token}",
                f"case_{token}": f"case_one_{token}",
                f"CSV-Only-{token}": f"csv_old_{token}",
            }
            v3 = {
                f"service-port-{token}": f"new_{token}",
                f"GAP_KEY_{token}": f"gap_new_{token}",
                f"STABLE-{token}": f"same_{token}",
                f"CASE-{token}": f"case_two_{token}",
                f"csv_only_{token}": f"csv_new_{token}",
                f"Newest-Only-{token}": f"new_only_{token}",
            }

            write_fixtures(v1, v2, v3)
            run_submission()
            expected = expected_rows([v1, v2, v3])
            actual = read_output()
            assert actual == expected, (
                "The Rust program produced an incorrect report for unseen input files. "
                f"Expected {expected}, got {actual}"
            )
    finally:
        for path, contents in original_files.items():
            path.write_bytes(contents)
        if original_output is None:
            OUTPUT.unlink(missing_ok=True)
        else:
            OUTPUT.parent.mkdir(parents=True, exist_ok=True)
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
