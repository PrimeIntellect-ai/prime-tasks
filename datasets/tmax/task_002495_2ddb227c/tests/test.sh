#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import pytest


def run_command(command, cwd, timeout=180):
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command failed: {' '.join(command)}\n{result.stdout}"
    return result.stdout


def test_legacy_builder_fixed():
    makefile_path = "/home/user/legacy_builder/Makefile"
    assert os.path.isfile(makefile_path), f"{makefile_path} is missing"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "\t" in content, "Makefile should be fixed to use tabs instead of spaces"

    pack_c_path = "/home/user/legacy_builder/pack.c"
    assert os.path.isfile(pack_c_path), f"{pack_c_path} is missing"
    with open(pack_c_path, "r") as f:
        content = f.read()
    assert "<stdio.h>" in content, "pack.c should include <stdio.h>"

    builder_path = "/home/user/legacy_builder/builder"
    assert os.path.isfile(builder_path), f"{builder_path} executable is missing. Did you run make?"
    assert os.access(builder_path, os.X_OK), f"{builder_path} should be executable"


def test_legacy_output():
    output_path = "/home/user/legacy_output.txt"
    assert os.path.isfile(output_path), f"{output_path} is missing"
    with open(output_path, "r") as f:
        content = f.read().strip()
    assert content == "Packaging release...", f"Unexpected content in {output_path}: {content}"


def test_rust_project_exists():
    cargo_toml = "/home/user/release_eval/Cargo.toml"
    assert os.path.isfile(cargo_toml), f"{cargo_toml} is missing. Did you create the Rust project?"

    main_rs = "/home/user/release_eval/src/main.rs"
    assert os.path.isfile(main_rs), f"{main_rs} is missing"

    with open(main_rs, "r") as f:
        content = f.read()
    assert "#[test]" in content, "src/main.rs must contain at least one unit test using #[test]"


def test_input_files():
    env_path = "/home/user/release.env"
    assert os.path.isfile(env_path), f"{env_path} is missing"

    conditions_path = "/home/user/conditions.txt"
    assert os.path.isfile(conditions_path), f"{conditions_path} is missing"


def test_eval_results():
    results_path = "/home/user/eval_results.json"
    assert os.path.isfile(results_path), f"{results_path} is missing. Did you run the Rust application?"

    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} does not contain valid JSON")

    expected = {
        "OS == linux": True,
        "STAGE == prod": False,
        "ARCH == x86_64 AND STAGE == beta": True
    }

    assert data == expected, f"Evaluation results in {results_path} do not match the expected output"


def test_actual_builds_tests_and_runtime_behavior():
    legacy_dir = "/home/user/legacy_builder"
    builder_path = os.path.join(legacy_dir, "builder")
    object_path = os.path.join(legacy_dir, "pack.o")
    for path in (builder_path, object_path):
        if os.path.exists(path):
            os.remove(path)

    run_command(["make", "-B", "builder"], legacy_dir)
    assert os.path.isfile(builder_path), "make did not produce the builder executable"
    with open(builder_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "builder must be a compiled executable"
    builder_output = run_command(["./builder"], legacy_dir).strip()
    assert builder_output == "Packaging release...", "The rebuilt builder produced unexpected output"

    rust_dir = "/home/user/release_eval"
    run_command(["cargo", "test", "--quiet"], rust_dir, timeout=300)
    listed_tests = run_command(
        ["cargo", "test", "--bin", "release_eval", "--", "--list"],
        rust_dir,
        timeout=300,
    )
    assert re.search(r"(?m)^.+: test$", listed_tests), "release_eval must contain a compiled unit test"

    env_path = "/home/user/release.env"
    conditions_path = "/home/user/conditions.txt"
    results_path = "/home/user/eval_results.json"
    paths = (env_path, conditions_path, results_path)
    backups = {}
    for path in paths:
        with open(path, "rb") as f:
            backups[path] = f.read()

    fixed_expected = {
        "OS == linux": True,
        "STAGE == prod": False,
        "ARCH == x86_64 AND STAGE == beta": True,
    }

    try:
        assert backups[env_path].decode().splitlines() == [
            "OS=linux", "ARCH=x86_64", "STAGE=beta"
        ], "release.env does not contain the required input"
        assert backups[conditions_path].decode().splitlines() == list(fixed_expected), \
            "conditions.txt does not contain the required rules"

        os.remove(results_path)
        run_command(["cargo", "run", "--quiet"], rust_dir, timeout=300)
        assert os.path.isfile(results_path), "cargo run did not generate eval_results.json"
        with open(results_path) as f:
            assert json.load(f) == fixed_expected, "The Rust application failed on the required inputs"

        for _ in range(2):
            suffix = secrets.token_hex(8).upper()
            key_a = "VAR_A_" + suffix
            key_b = "VAR_B_" + suffix
            value_a = secrets.token_hex(12)
            value_b = secrets.token_hex(12)
            wrong = secrets.token_hex(12)
            while wrong in (value_a, value_b):
                wrong = secrets.token_hex(12)

            rules = [
                f"{key_a} == {value_a}",
                f"{key_a} == {wrong}",
                f"{key_a} == {value_a} AND {key_b} == {value_b}",
                f"{key_a} == {value_a} AND {key_b} == {wrong}",
                f"MISSING_{suffix} == {value_a}",
            ]
            expected = {
                rules[0]: True,
                rules[1]: False,
                rules[2]: True,
                rules[3]: False,
                rules[4]: False,
            }

            with open(env_path, "w") as f:
                f.write(f"{key_a}={value_a}\n{key_b}={value_b}\n")
            with open(conditions_path, "w") as f:
                f.write("\n".join(rules) + "\n")
            if os.path.exists(results_path):
                os.remove(results_path)

            run_command(["cargo", "run", "--quiet"], rust_dir, timeout=300)
            assert os.path.isfile(results_path), "The application did not generate results for runtime inputs"
            with open(results_path) as f:
                actual = json.load(f)
            assert actual == expected, "The application did not correctly parse and evaluate runtime rules"
    finally:
        for path, content in backups.items():
            with open(path, "wb") as f:
                f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
