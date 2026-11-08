#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT_DIR = Path("/home/user/processor")
MANIFEST = PROJECT_DIR / "Cargo.toml"
INPUT_FILE = Path("/home/user/telemetry_raw.csv")
OUTPUT_FILE = Path("/home/user/cleaned_telemetry.csv")
CARGO = "/opt/rust/cargo/bin/cargo"


def cargo_env():
    env = os.environ.copy()
    env["RUSTUP_HOME"] = "/opt/rust/rustup"
    env["CARGO_HOME"] = "/opt/rust/cargo"
    env["PATH"] = "/opt/rust/cargo/bin:" + env.get("PATH", "")
    return env


def test_rust_project_exists():
    """Verify that the Rust project was created at the expected location."""
    project_dir = "/home/user/processor"
    cargo_toml = os.path.join(project_dir, "Cargo.toml")

    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} does not exist."
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found in {project_dir}. Is it a valid Cargo project?"


def test_rust_source_exists():
    sources = [p for p in PROJECT_DIR.rglob("*.rs") if "target" not in p.parts]
    assert sources, "No Rust source files were found in the Cargo project."


def test_cleaned_telemetry_output():
    """Verify that the output file exists and has the correct processed content."""
    output_file = "/home/user/cleaned_telemetry.csv"

    assert os.path.isfile(output_file), f"Output file {output_file} was not generated."

    expected_content = """timestamp,rolling_avg
1700000100,10.00
1700000101,11.00
1700000102,11.33
1700000103,12.00
1700000104,13.00
1700000105,14.00
1700000106,15.00
1700000107,16.00"""

    with open(output_file, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The content of {output_file} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )


def make_fixture():
    base = 1800000000 + secrets.randbelow(10000000)
    values = [20 + secrets.randbelow(60) for _ in range(4)]
    rows = [
        (base, f"channel=7 temp_val={values[0]}.0"),
        (base + 1, f"noise val={values[1]}.0C"),
        (base + 3, f"[WARN] val={values[2]}.0"),
        (base + 4, "status=999; val=oops"),
        (base + 6, f"ERR: val={values[3]}.0"),
    ]
    return rows


def expected_for(rows):
    extraction = re.compile(r"val=([+-]?(?:\d+(?:\.\d*)?|\.\d+))")
    by_timestamp = {timestamp: sensor_data for timestamp, sensor_data in rows}
    earliest = min(by_timestamp)
    latest = max(by_timestamp)
    resampled = []
    last_value = None

    for timestamp in range(earliest, latest + 1):
        if timestamp in by_timestamp:
            match = extraction.search(by_timestamp[timestamp])
            if match:
                last_value = float(match.group(1))
        assert last_value is not None
        resampled.append((timestamp, last_value))

    lines = ["timestamp,rolling_avg"]
    for index, (timestamp, _) in enumerate(resampled):
        window = [value for _, value in resampled[max(0, index - 2):index + 1]]
        lines.append(f"{timestamp},{sum(window) / len(window):.2f}")
    return "\n".join(lines)


def write_fixture(rows):
    with INPUT_FILE.open("w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["timestamp", "sensor_data"])
        writer.writerows(rows)


def run_target(package, binary):
    if OUTPUT_FILE.exists():
        OUTPUT_FILE.unlink()
    return subprocess.run(
        [CARGO, "run", "--quiet", "--manifest-path", str(MANIFEST), "-p", package, "--bin", binary],
        cwd=PROJECT_DIR,
        env=cargo_env(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )


def test_build_and_execute_rust_pipeline_on_derived_inputs():
    original_input = INPUT_FILE.read_bytes()
    original_output = OUTPUT_FILE.read_bytes() if OUTPUT_FILE.exists() else None

    try:
        clean = subprocess.run(
            [CARGO, "clean", "--manifest-path", str(MANIFEST)],
            cwd=PROJECT_DIR,
            env=cargo_env(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}\n{clean.stderr}"

        build = subprocess.run(
            [CARGO, "build", "--bins", "--manifest-path", str(MANIFEST)],
            cwd=PROJECT_DIR,
            env=cargo_env(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        assert build.returncode == 0, f"The Rust project did not build:\n{build.stdout}\n{build.stderr}"

        metadata_result = subprocess.run(
            [CARGO, "metadata", "--no-deps", "--format-version", "1", "--manifest-path", str(MANIFEST)],
            cwd=PROJECT_DIR,
            env=cargo_env(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert metadata_result.returncode == 0, metadata_result.stderr
        metadata = json.loads(metadata_result.stdout)

        candidates = []
        project_root = PROJECT_DIR.resolve()
        for package in metadata["packages"]:
            for target in package["targets"]:
                source = Path(target["src_path"]).resolve()
                try:
                    source.relative_to(project_root)
                except ValueError:
                    continue
                if "bin" in target["kind"] and source.suffix == ".rs":
                    candidates.append((package["name"], target["name"]))
        assert candidates, "The Cargo project has no Rust binary target under /home/user/processor."

        first_rows = make_fixture()
        first_expected = expected_for(first_rows)
        write_fixture(first_rows)

        selected = None
        diagnostics = []
        for package, binary in candidates:
            result = run_target(package, binary)
            actual = OUTPUT_FILE.read_text().strip() if OUTPUT_FILE.exists() else "<output not generated>"
            if result.returncode == 0 and actual == first_expected:
                selected = (package, binary)
                break
            diagnostics.append(
                f"{package}/{binary}: exit={result.returncode}\nstdout={result.stdout}\nstderr={result.stderr}\noutput={actual}"
            )

        assert selected is not None, (
            "No Rust binary correctly processed the generated telemetry input.\n"
            + "\n---\n".join(diagnostics)
        )

        second_rows = make_fixture()
        second_expected = expected_for(second_rows)
        write_fixture(second_rows)
        result = run_target(*selected)
        assert result.returncode == 0, f"Rust program failed on a second input:\n{result.stdout}\n{result.stderr}"
        assert OUTPUT_FILE.exists(), "Rust program did not generate cleaned_telemetry.csv."
        assert OUTPUT_FILE.read_text().strip() == second_expected, (
            "Rust program produced incorrect output for a second generated input.\n"
            f"Expected:\n{second_expected}\nActual:\n{OUTPUT_FILE.read_text().strip()}"
        )
    finally:
        INPUT_FILE.write_bytes(original_input)
        if original_output is None:
            if OUTPUT_FILE.exists():
                OUTPUT_FILE.unlink()
        else:
            OUTPUT_FILE.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
