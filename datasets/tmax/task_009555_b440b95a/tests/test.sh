#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import subprocess
import sys
import tempfile

import pytest

APP_PATH = "/home/user/legacy_app/app.py"
APP_DIR = "/home/user/legacy_app"
OUTPUT_PATH = "/home/user/legacy_app/output.txt"


@pytest.fixture(scope="session", autouse=True)
def run_application():
    assert os.path.isfile(APP_PATH), f"File {APP_PATH} does not exist."
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [sys.executable, APP_PATH],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Running app.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_app_module():
    spec = importlib.util.spec_from_file_location("legacy_app_under_test", APP_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_output_file_exists_and_correct():
    output_path = "/home/user/legacy_app/output.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. Did you run the script and save the output?"

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["1.0", "20.0", "3.5"]
    assert lines == expected_lines, f"Contents of {output_path} do not match the expected equilibrium values. Got {lines}, expected {expected_lines}."


def test_app_py_still_exists_and_recursive():
    app_path = "/home/user/legacy_app/app.py"
    assert os.path.isfile(app_path), f"File {app_path} does not exist."

    with open(app_path, "r") as f:
        content = f.read()

    assert "def find_equilibrium" in content, "The find_equilibrium function must remain in app.py."
    assert "find_equilibrium(" in content.replace("def find_equilibrium", ""), "The function must remain recursive."


def test_find_equilibrium_uses_tolerance_and_real_recursion():
    app = load_app_module()
    assert callable(getattr(app, "find_equilibrium", None))

    original = app.find_equilibrium
    calls = []

    def tracked(current, target, rate):
        calls.append((current, target, rate))
        return original(current, target, rate)

    app.find_equilibrium = tracked

    # A value already within 1e-5, including from above the target, must be
    # accepted immediately rather than recursing past the target.
    value = tracked(2.000006, 2.0, 0.1)
    assert abs(value - 2.0) <= 1e-5
    assert len(calls) == 1, "A value within the required tolerance should terminate immediately."

    # This case is not exactly representable in binary floating point. It must
    # advance recursively by the supplied rate and terminate near the target.
    calls.clear()
    value = tracked(0.0, 0.3, 0.1)
    assert abs(value - 0.3) <= 1e-5
    assert len(calls) >= 2, "find_equilibrium must perform recursive calls."
    for previous, current in zip(calls, calls[1:]):
        assert abs((current[0] - previous[0]) - previous[2]) < 1e-12, (
            "Recursive steps must advance current by rate."
        )


def test_process_data_on_additional_inputs():
    app = load_app_module()
    cases = [
        (1.0, 1.7, 0.1),
        (4.0, 5.4, 0.2),
        (7.5, 8.4, 0.1),
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "data.txt")
        output_path = os.path.join(tmpdir, "output.txt")
        with open(input_path, "w") as f:
            for current, target, rate in cases:
                f.write(f"{current},{target},{rate}\n")

        app.process_data(input_path, output_path)

        with open(output_path, "r") as f:
            actual = [line.rstrip("\n") for line in f]

    expected = [f"{target:.1f}" for _, target, _ in cases]
    assert actual == expected, f"Got {actual}, expected {expected}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
