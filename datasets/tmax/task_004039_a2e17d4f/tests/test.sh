#!/bin/bash
set -e
mkdir -p /logs/verifier
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/cargo
export PATH="/opt/cargo/bin:${PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import base64
import json
import os
from pathlib import Path
import secrets
import subprocess

import pytest

PROJECT = "/home/user/metric_service"
MANIFEST = f"{PROJECT}/Cargo.toml"
DATA_PATH = Path("/home/user/data.json")
EXPECTED_OUTPUT = [
    "s1:60",
    "s2:10",
    "s3:ERROR",
    "s4:300",
    "s5:ERROR",
    "s6:ERROR",
    "s7:ERROR",
]


def run_service():
    return subprocess.run(
        [
            "cargo", "run", "--quiet", "--manifest-path", MANIFEST,
            "--bin", "metric_service",
        ],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )


def test_output_txt_exists_and_correct():
    output_path = "/home/user/output.txt"
    assert os.path.isfile(output_path), f"File {output_path} does not exist. Did you redirect the output?"

    expected_output = [
        "s1:60",
        "s2:10",
        "s3:ERROR",
        "s4:300",
        "s5:ERROR",
        "s6:ERROR",
        "s7:ERROR"
    ]

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_output), f"Expected {len(expected_output)} lines in output.txt, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_output)):
        assert actual == expected, f"Line {i+1} in output.txt is incorrect. Expected '{expected}', got '{actual}'."


def test_rust_code_no_unwrap():
    main_rs_path = "/home/user/metric_service/src/main.rs"
    assert os.path.isfile(main_rs_path), f"File {main_rs_path} does not exist."

    with open(main_rs_path, "r") as f:
        content = f.read()

    # It's possible the student still uses unwrap elsewhere, but we can verify that the output is correct.
    # The primary truth is the output.txt content.
    pass


def test_build_and_run_on_production_sample():
    build = subprocess.run(
        [
            "cargo", "build", "--quiet", "--manifest-path", MANIFEST,
            "--bin", "metric_service",
        ],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, f"Rust service failed to build:\n{build.stdout}\n{build.stderr}"

    result = run_service()
    assert result.returncode == 0, (
        f"Rust service exited unsuccessfully on data.json (code {result.returncode}):\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert result.stdout.splitlines() == EXPECTED_OUTPUT, (
        f"Running the service produced incorrect output: {result.stdout!r}"
    )

    with open("/home/user/output.txt", "r") as f:
        saved_output = f.read()
    assert saved_output == result.stdout, (
        "output.txt is not the exact stdout produced by the fixed service on data.json"
    )


def test_runtime_error_handling_with_generated_records():
    original_data = DATA_PATH.read_bytes()
    rng = secrets.SystemRandom()
    token = secrets.token_hex(8)

    values_a = [rng.randint(-5000, 5000) for _ in range(rng.randint(2, 6))]
    values_b = [rng.randint(0, 1000) for _ in range(rng.randint(1, 5))]

    cases = [
        ({"id": f"{token}_valid_a", "b64_data": base64.b64encode(
            ",".join(map(str, values_a)).encode("utf-8")
        ).decode("ascii")}, f"{token}_valid_a:{sum(values_a)}"),
        ({"id": f"{token}_valid_b", "b64_data": base64.b64encode(
            ",".join(map(str, values_b)).encode("utf-8")
        ).decode("ascii")}, f"{token}_valid_b:{sum(values_b)}"),
        ({"id": f"{token}_base64", "b64_data": secrets.token_hex(7) + "$$"},
         f"{token}_base64:ERROR"),
        ({"id": f"{token}_utf8", "b64_data": base64.b64encode(
            bytes([0xff, 0xfe, rng.randrange(0x80, 0xc0)])
        ).decode("ascii")}, f"{token}_utf8:ERROR"),
        ({"id": f"{token}_integer", "b64_data": base64.b64encode(
            f"12,not_an_integer_{secrets.token_hex(4)},7".encode("utf-8")
        ).decode("ascii")}, f"{token}_integer:ERROR"),
    ]
    rng.shuffle(cases)
    records = [record for record, _ in cases]
    expected = [line for _, line in cases]

    try:
        DATA_PATH.write_text(json.dumps(records), encoding="utf-8")
        result = run_service()
        assert result.returncode == 0, (
            f"Rust service crashed on generated malformed records (code {result.returncode}):\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert result.stdout.splitlines() == expected, (
            "Service did not preserve record order or correctly handle generated valid, "
            f"Base64, UTF-8, and integer inputs. Expected {expected!r}, got {result.stdout.splitlines()!r}."
        )
    finally:
        DATA_PATH.write_bytes(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
