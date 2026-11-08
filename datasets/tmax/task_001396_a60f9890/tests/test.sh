#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import shutil
import subprocess

import pytest

PROJECT = "/home/user/project"
RUST_DIR = os.path.join(PROJECT, "rust_lib")
BUILD_DIR = os.path.join(PROJECT, "build")
LIB_PATH = os.path.join(RUST_DIR, "target", "release", "librate_eval.so")
RUNNER_PATH = os.path.join(BUILD_DIR, "runner")


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_test_project():
    build = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=RUST_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert build.returncode == 0, f"cargo build --release failed:\n{build.stdout}"

    tests = subprocess.run(
        ["cargo", "test"],
        cwd=RUST_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert tests.returncode == 0, f"cargo test failed:\n{tests.stdout}"
    assert "test_evaluate_rule_properties" in tests.stdout, (
        "The executed cargo test suite did not contain test_evaluate_rule_properties.\n"
        + tests.stdout
    )

    shutil.rmtree(BUILD_DIR, ignore_errors=True)
    configure = subprocess.run(
        ["cmake", "-S", PROJECT, "-B", BUILD_DIR],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert configure.returncode == 0, f"cmake configuration failed:\n{configure.stdout}"

    compile_result = subprocess.run(
        ["cmake", "--build", BUILD_DIR],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert compile_result.returncode == 0, f"CMake build failed:\n{compile_result.stdout}"


def test_cargo_test_log_exists_and_passed():
    log_path = "/home/user/cargo_test.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did you redirect cargo test output?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "test_evaluate_rule_properties" in content, "The proptest 'test_evaluate_rule_properties' was not found in cargo_test.log."
    assert "ok" in content or "passed" in content, "cargo_test.log does not indicate successful test execution."


def test_runner_output_log_correct():
    log_path = "/home/user/runner_output.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did you run the executable and redirect output?"

    with open(log_path, "r") as f:
        content = f.read()

    assert "Res1: 1" in content, "runner_output.log is missing 'Res1: 1' (Expected rule MAX:10 with 5 reqs to be allowed)."
    assert "Res2: 0" in content, "runner_output.log is missing 'Res2: 0' (Expected rule MAX:10 with 15 reqs to be denied)."
    assert "Res3: -1" in content, "runner_output.log is missing 'Res3: -1' (Expected INVALID rule to return error)."


def test_runner_executable_exists_and_linked():
    assert os.path.isfile(RUNNER_PATH), f"{RUNNER_PATH} does not exist. Did you run cmake and make?"
    assert os.access(RUNNER_PATH, os.X_OK), f"{RUNNER_PATH} is not executable."

    try:
        ldd_output = subprocess.check_output(["ldd", RUNNER_PATH], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run ldd on {RUNNER_PATH}: {e.output}")

    assert "librate_eval.so" in ldd_output, "runner is not dynamically linked against librate_eval.so."


def test_proptest_dependency_added():
    cargo_toml_path = os.path.join(RUST_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml_path), f"{cargo_toml_path} does not exist."

    with open(cargo_toml_path, "r") as f:
        content = f.read()

    assert "proptest" in content, "proptest crate was not found in Cargo.toml."

    metadata = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=RUST_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert metadata.returncode == 0, metadata.stderr
    package = json.loads(metadata.stdout)["packages"][0]
    assert any(d["name"] == "proptest" and d.get("kind") == "dev" for d in package["dependencies"]), (
        "proptest must be declared as a dev-dependency"
    )

    source = open(os.path.join(RUST_DIR, "src", "lib.rs"), "r").read()
    assert re.search(r"proptest\s*!", source), "The Rust source does not use the proptest! macro."
    assert "test_evaluate_rule_properties" in source


def test_evaluate_rule_on_derived_varied_inputs():
    assert os.path.isfile(LIB_PATH), f"Release library was not produced at {LIB_PATH}"
    library = ctypes.CDLL(LIB_PATH)
    evaluate = library.evaluate_rule
    evaluate.argtypes = [ctypes.c_char_p, ctypes.c_int]
    evaluate.restype = ctypes.c_int

    rng = random.Random(947231)
    cases = [(0, 0), (0, 1), (1, 0), (10, 10), (10, 11), (1000, 1500)]
    cases.extend((rng.randint(0, 1000), rng.randint(0, 1500)) for _ in range(80))
    for maximum, count in cases:
        rule = f"MAX:{maximum}".encode("ascii")
        expected = 1 if count <= maximum else 0
        assert evaluate(rule, count) == expected, f"Wrong result for MAX:{maximum}, count={count}"

    invalid_rules = [b"", b"INVALID", b"MAX:", b"MAX:-1", b"MAX:+1", b"max:10", b"MAX:1x", b" MAX:10", b"MAX:10 "]
    for rule in invalid_rules:
        assert evaluate(rule, 5) == -1, f"Invalid rule {rule!r} was not rejected"
    assert evaluate(None, 5) == -1, "A null rule pointer was not rejected"


def test_built_runner_really_executes_library_function():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = os.path.dirname(LIB_PATH) + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    result = subprocess.run(
        [RUNNER_PATH], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert result.returncode == 0, f"runner failed:\n{result.stderr}"
    assert "Res1: 1" in result.stdout
    assert "Res2: 0" in result.stdout
    assert "Res3: -1" in result.stdout

    shim_source = "/tmp/rate_eval_shim.c"
    shim_library = "/tmp/librate_eval_shim.so"
    with open(shim_source, "w") as f:
        f.write("int evaluate_rule(const char *rule, int count) { (void)rule; (void)count; return 77; }\n")
    shim_build = subprocess.run(
        ["cc", "-shared", "-fPIC", shim_source, "-o", shim_library],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert shim_build.returncode == 0, shim_build.stdout

    shim_env = env.copy()
    shim_env["LD_PRELOAD"] = shim_library
    interposed = subprocess.run(
        [RUNNER_PATH], env=shim_env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert interposed.returncode == 0, interposed.stderr
    assert "Res1: 77" in interposed.stdout
    assert "Res2: 77" in interposed.stdout
    assert "Res3: 77" in interposed.stdout
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
