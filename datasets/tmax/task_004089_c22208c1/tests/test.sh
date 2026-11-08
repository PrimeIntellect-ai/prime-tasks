#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import tempfile


def test_crash_file_correct():
    crash_file_path = "/home/user/crash_file.txt"
    assert os.path.isfile(crash_file_path), f"File {crash_file_path} is missing."

    with open(crash_file_path, "r") as f:
        content = f.read().strip()

    expected = "batch_C broken.txt"
    assert content == expected, f"Expected crash_file.txt to contain '{expected}', but found '{content}'."


def test_fuzz_test_exists_and_valid():
    test_file_path = "/home/user/calc/calc_test.go"
    assert os.path.isfile(test_file_path), f"Fuzz test file {test_file_path} is missing."

    with open(test_file_path, "r") as f:
        content = f.read()

    assert "func FuzzCalculate" in content, "Could not find 'func FuzzCalculate' in calc_test.go."
    assert "testing.F" in content, "The fuzz test does not appear to use the '*testing.F' type."

    # Build and exercise the submitted fuzz target in an isolated package copy.
    # Add the actual crashing file as verifier-controlled seed corpus so the
    # result does not depend on random fuzz input generation.
    crash_name = open("/home/user/crash_file.txt", "r").read().strip()
    crash_data_path = os.path.join("/home/user/data", crash_name)
    with open(crash_data_path, "rb") as f:
        crash_data = f.read()

    with tempfile.TemporaryDirectory() as package_dir:
        for name in ("calc.go", "calc_test.go", "go.mod"):
            shutil.copy2(os.path.join("/home/user/calc", name), package_dir)
        go_sum = "/home/user/calc/go.sum"
        if os.path.isfile(go_sum):
            shutil.copy2(go_sum, package_dir)

        corpus_dir = os.path.join(package_dir, "testdata", "fuzz", "FuzzCalculate")
        os.makedirs(corpus_dir, exist_ok=True)
        seed_text = crash_data.decode("utf-8")
        with open(os.path.join(corpus_dir, "verifier_seed"), "w") as f:
            f.write("go test fuzz v1\n")
            f.write("[]byte(" + json.dumps(seed_text) + ")\n")

        env = os.environ.copy()
        env["GOMAXPROCS"] = "2"

        compile_result = subprocess.run(
            ["go", "test", "-count=1", "-run=^$"],
            cwd=package_dir,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
        )
        assert compile_result.returncode == 0, (
            "calc_test.go does not compile as a Go test:\n" + compile_result.stdout
        )

        run_result = subprocess.run(
            ["go", "test", "-count=1", "-run=FuzzCalculate"],
            cwd=package_dir,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
        )
        output = run_result.stdout
        assert run_result.returncode != 0, (
            "FuzzCalculate did not expose the panic on the crashing input.\n" + output
        )
        assert "runtime error: index out of range" in output, (
            "FuzzCalculate failed, but did not expose the expected out-of-bounds panic.\n" + output
        )
        assert re.search(r"calc\.Calculate\(", output), (
            "The reported panic did not originate in Calculate.\n" + output
        )


def test_accumulator_value_correct():
    accumulator_file_path = "/home/user/accumulator.txt"
    assert os.path.isfile(accumulator_file_path), f"File {accumulator_file_path} is missing."

    with open(accumulator_file_path, "r") as f:
        content = f.read().strip()

    expected = "56"
    assert content == expected, f"Expected accumulator.txt to contain '{expected}', but found '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
