#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

REPO = "/home/user/repo"
BUILD = os.path.join(REPO, "build")


def test_output_results_exists_and_correct():
    output_path = "/home/user/output_results.json"
    inputs_path = "/home/user/repo/data/inputs.json"

    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.exists(inputs_path), f"Input file {inputs_path} does not exist."

    with open(inputs_path, "r") as f:
        try:
            inputs = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse {inputs_path} as JSON.")

    expected_results = []
    for item in inputs:
        x = item.get("input_x")
        y = item.get("input_y")
        assert x is not None and y is not None, "Input items must contain 'input_x' and 'input_y'."
        expected_results.append({
            "x": x,
            "y": y,
            "result": 3 * (x ** 2) + 2 * y
        })

    with open(output_path, "r") as f:
        try:
            outputs = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse {output_path} as JSON.")

    assert isinstance(outputs, list), f"Expected {output_path} to contain a JSON array."
    assert len(outputs) == len(expected_results), f"Expected {len(expected_results)} results, found {len(outputs)}."

    for i, (actual, expected) in enumerate(zip(outputs, expected_results)):
        assert actual == expected, f"Result at index {i} is incorrect. Expected {expected}, got {actual}."


def test_libraries_built():
    assert os.path.exists(BUILD), f"Build directory {BUILD} does not exist."

    mathwrap_so = os.path.join(BUILD, "libmathwrap.so")
    fastmath_so = os.path.join(BUILD, "libfastmath.so")

    assert os.path.exists(mathwrap_so), f"Library {mathwrap_so} was not built."
    assert os.path.exists(fastmath_so), f"Library {fastmath_so} was not built."


def test_cmakelists_fixed():
    cmakelists_path = "/home/user/repo/CMakeLists.txt"
    assert os.path.exists(cmakelists_path), f"File {cmakelists_path} does not exist."

    with open(cmakelists_path, "r") as f:
        content = f.read()

    assert "target_link_libraries" in content and "mathwrap" in content and "fastmath" in content, \
        "CMakeLists.txt does not appear to link mathwrap against fastmath."


def test_assembly_bug_fixed():
    asm_path = "/home/user/repo/src/fast_math.s"
    assert os.path.exists(asm_path), f"File {asm_path} does not exist."

    with open(asm_path, "r") as f:
        content = f.read()

    assert "add $2, %rcx" not in content, "The assembly bug (add $2, %rcx) is still present."


@pytest.fixture(scope="session")
def clean_build():
    build_dir = tempfile.mkdtemp(prefix="verified-math-build-")
    try:
        configured = subprocess.run(
            ["cmake", "-S", REPO, "-B", build_dir],
            text=True, capture_output=True, timeout=120
        )
        assert configured.returncode == 0, (
            "CMake configuration failed:\n" + configured.stdout + configured.stderr
        )
        compiled = subprocess.run(
            ["cmake", "--build", build_dir, "--parallel", "2"],
            text=True, capture_output=True, timeout=120
        )
        assert compiled.returncode == 0, (
            "A clean build from the submitted sources failed:\n"
            + compiled.stdout + compiled.stderr
        )
        yield build_dir
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def generated_cases():
    cases = [
        [0, 0],
        [-7, 19],
        [11, -23],
        [2, 3000000123],
        [-3, -3000000456],
    ]
    rng = secrets.SystemRandom()
    for _ in range(8):
        cases.append([rng.randint(-1000000, 1000000), rng.randint(-10**12, 10**12)])
    return cases


def run_library_checks(build_dir, cases):
    script = r'''
import ctypes
import json
import os
import sys

build_dir = sys.argv[1]
cases = json.loads(sys.argv[2])

# Loading mathwrap first verifies that its dependency on fastmath is usable.
mathwrap = ctypes.CDLL(os.path.join(build_dir, "libmathwrap.so"))
wrapper = mathwrap.compute_wrapper
wrapper.argtypes = [ctypes.c_long, ctypes.c_long]
wrapper.restype = ctypes.c_long

# Explicitly load and execute the assembly library as well.
fastmath = ctypes.CDLL(os.path.join(build_dir, "libfastmath.so"))
poly = fastmath.compute_poly
poly.argtypes = [ctypes.c_long, ctypes.c_long]
poly.restype = ctypes.c_long

for x, y in cases:
    expected = 3 * x * x + 2 * y
    actual_poly = poly(x, y)
    actual_wrapper = wrapper(x, y)
    assert actual_poly == expected, (x, y, expected, actual_poly)
    assert actual_wrapper == expected, (x, y, expected, actual_wrapper)
'''
    env = os.environ.copy()
    old_path = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = build_dir + ((":" + old_path) if old_path else "")
    checked = subprocess.run(
        ["python3", "-c", script, build_dir, json.dumps(cases)],
        env=env, text=True, capture_output=True, timeout=30
    )
    assert checked.returncode == 0, (
        f"Shared-library execution failed for {build_dir}:\n"
        + checked.stdout + checked.stderr
    )


def test_built_libraries_execute_correctly():
    run_library_checks(BUILD, generated_cases())


def test_clean_rebuild_libraries_execute_correctly(clean_build):
    assert os.path.isfile(os.path.join(clean_build, "libmathwrap.so"))
    assert os.path.isfile(os.path.join(clean_build, "libfastmath.so"))
    run_library_checks(clean_build, generated_cases())


def test_flask_compute_endpoint_executes():
    server_path = os.path.join(REPO, "api", "server.py")
    assert os.path.isfile(server_path), f"File {server_path} does not exist."
    cases = generated_cases()
    script = r'''
import importlib.util
import json
import sys

server_path = sys.argv[1]
cases = json.loads(sys.argv[2])
spec = importlib.util.spec_from_file_location("submitted_math_server", server_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert hasattr(module, "app"), "server.py does not expose the Flask app"
client = module.app.test_client()

for x, y in cases:
    response = client.post("/compute", json={"x": x, "y": y})
    assert response.status_code == 200, (x, y, response.status_code, response.get_data(as_text=True))
    assert response.is_json, (x, y, response.content_type)
    expected = {"result": 3 * x * x + 2 * y}
    assert response.get_json() == expected, (x, y, expected, response.get_json())
'''
    env = os.environ.copy()
    old_path = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = BUILD + ((":" + old_path) if old_path else "")
    checked = subprocess.run(
        ["python3", "-c", script, server_path, json.dumps(cases)],
        env=env, text=True, capture_output=True, timeout=30
    )
    assert checked.returncode == 0, (
        "The Flask /compute endpoint failed behavioral tests:\n"
        + checked.stdout + checked.stderr
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
