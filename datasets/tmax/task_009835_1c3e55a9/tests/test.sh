#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import subprocess

import pytest

CARGO_TOML_PATH = "/home/user/bcd_eval/Cargo.toml"
BCD_CONFIG_PATH = "/home/user/build_config.bcd"
JSON_OUTPUT_PATH = "/home/user/mobile_mock.json"


def run_program():
    return subprocess.run(
        ["cargo", "run", "--manifest-path", CARGO_TOML_PATH],
        capture_output=True,
        text=True,
        timeout=180,
    )


def evaluate_bcd(content):
    """Independent evaluator used to derive expected output for generated inputs."""
    values = {}
    for raw_line in content.splitlines():
        if not raw_line.strip():
            continue
        key, value = raw_line.split(" = ", 1)
        if value.startswith("/"):
            values[key] = value
            continue

        tokens = value.split()
        if len(tokens) == 1 and re.fullmatch(r"-?\d+", tokens[0]):
            values[key] = int(tokens[0])
            continue

        stack = []
        for token in tokens:
            if token in ("+", "*"):
                right = stack.pop()
                left = stack.pop()
                stack.append(left + right if token == "+" else left * right)
            elif re.fullmatch(r"-?\d+", token):
                stack.append(int(token))
            else:
                stack.append(values[token])
        assert len(stack) == 1
        values[key] = stack[0]
    return values


def random_key(used):
    while True:
        key = "K" + secrets.token_hex(6)
        if key not in used and key != "RateLimit":
            used.add(key)
            return key


def test_rust_project_exists():
    """Ensure the Rust project was created at the correct path."""
    assert os.path.isfile(CARGO_TOML_PATH), f"Rust project Cargo.toml not found at {CARGO_TOML_PATH}"


def test_cargo_run_success_and_json_output():
    """Run the Rust program with the original config and verify the JSON output."""
    if os.path.exists(JSON_OUTPUT_PATH):
        os.remove(JSON_OUTPUT_PATH)

    result = run_program()

    assert result.returncode == 0, f"cargo run failed with exit code {result.returncode}. stderr: {result.stderr}"
    assert os.path.isfile(JSON_OUTPUT_PATH), f"Expected output file {JSON_OUTPUT_PATH} was not created."

    with open(JSON_OUTPUT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_OUTPUT_PATH} does not contain valid JSON.")

    expected_data = {
        "ScreenWidth": 1080,
        "ScreenHeight": 1920,
        "Multiplier": 4,
        "Buffer": 512,
        "MaxMemory": 8294912,
        "ApiEndpoint": "/api/v2/config",
        "RateLimit": 45,
        "BurstThreshold": 100,
    }

    assert data == expected_data, f"JSON output does not match expected values. Got: {data}"


def test_rate_limit_validation():
    """Modify the config to have RateLimit > 60 and verify the program exits with code 1."""
    backup_path = BCD_CONFIG_PATH + ".bak"
    shutil.copy(BCD_CONFIG_PATH, backup_path)

    try:
        with open(BCD_CONFIG_PATH, "r") as f:
            content = f.read()

        content = content.replace("RateLimit = 45", "RateLimit = 65")

        with open(BCD_CONFIG_PATH, "w") as f:
            f.write(content)

        result = run_program()

        assert result.returncode == 1, f"Expected exit code 1 when RateLimit > 60, but got {result.returncode}."
    finally:
        shutil.move(backup_path, BCD_CONFIG_PATH)


def test_generated_variables_and_rpn_expressions():
    """Exercise unpredictable variable names, strings, and multi-step RPN expressions."""
    used = set()
    first = random_key(used)
    second = random_key(used)
    factor = random_key(used)
    summed = random_key(used)
    scaled = random_key(used)
    rate_base = random_key(used)
    endpoint = random_key(used)
    after_rate = random_key(used)
    final = random_key(used)

    a = secrets.randbelow(40) + 3
    b = secrets.randbelow(40) + 5
    c = secrets.randbelow(7) + 2
    rb = secrets.randbelow(12) + 2
    path = "/generated/" + secrets.token_hex(8)

    content = "\n".join([
        f"{first} = {a}",
        f"{second} = {b}",
        f"{factor} = {c}",
        f"{summed} = {first} {second} +",
        f"{scaled} = {summed} {factor} * 7 +",
        f"{rate_base} = {rb}",
        f"{endpoint} = {path}",
        f"RateLimit = {rate_base} 3 * 2 +",
        f"{after_rate} = RateLimit {factor} * {first} +",
        f"{final} = {scaled} {after_rate} + 2 *",
    ]) + "\n"
    expected = evaluate_bcd(content)
    assert expected["RateLimit"] <= 60

    with open(BCD_CONFIG_PATH, "rb") as f:
        original = f.read()
    try:
        with open(BCD_CONFIG_PATH, "w") as f:
            f.write(content)
        if os.path.exists(JSON_OUTPUT_PATH):
            os.remove(JSON_OUTPUT_PATH)

        result = run_program()
        assert result.returncode == 0, f"Generated valid config failed. stderr: {result.stderr}"
        assert os.path.isfile(JSON_OUTPUT_PATH), "Generated config did not produce mobile_mock.json"
        with open(JSON_OUTPUT_PATH, "r") as f:
            data = json.load(f)
        assert data == expected, f"Generated config was evaluated incorrectly. Got {data}, expected {expected}"
    finally:
        with open(BCD_CONFIG_PATH, "wb") as f:
            f.write(original)


def test_generated_expression_rate_limit_validation():
    """Ensure validation uses the evaluated RateLimit rather than a literal source line."""
    used = set()
    base = random_key(used)
    unrelated = random_key(used)
    endpoint = random_key(used)
    high_base = secrets.randbelow(20) + 21
    content = "\n".join([
        f"{base} = {high_base}",
        f"{unrelated} = {base} 4 +",
        f"RateLimit = {base} 3 * 1 +",
        f"{endpoint} = /blocked/{secrets.token_hex(8)}",
    ]) + "\n"
    expected = evaluate_bcd(content)
    assert expected["RateLimit"] > 60

    with open(BCD_CONFIG_PATH, "rb") as f:
        original = f.read()
    try:
        with open(BCD_CONFIG_PATH, "w") as f:
            f.write(content)
        if os.path.exists(JSON_OUTPUT_PATH):
            os.remove(JSON_OUTPUT_PATH)

        result = run_program()
        assert result.returncode == 1, f"Expected exit code 1 for evaluated RateLimit {expected['RateLimit']}, got {result.returncode}."
        assert result.stderr.strip(), "Rate-limit failure must print an error to standard error."
        assert not os.path.exists(JSON_OUTPUT_PATH), "A rejected configuration must not produce the JSON fixture."
    finally:
        with open(BCD_CONFIG_PATH, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
