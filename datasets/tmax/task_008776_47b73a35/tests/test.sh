#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import json
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

import pytest

PROJECT_DIR = Path("/home/user/expr-eval")
RESULTS_PATH = Path("/home/user/test_results.txt")
LIB_PATH = PROJECT_DIR / "src/lib.rs"
TEST_PATH = PROJECT_DIR / "tests/test_eval.py"


@pytest.fixture(scope="session")
def built_extension():
    wheel_dir = Path(tempfile.mkdtemp(prefix="rpn-wheels-"))
    install_dir = Path(tempfile.mkdtemp(prefix="rpn-install-"))

    build = subprocess.run(
        [
            "maturin", "build",
            "--manifest-path", str(PROJECT_DIR / "Cargo.toml"),
            "--interpreter", sys.executable,
            "--out", str(wheel_dir),
        ],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, (
        "Failed to build the Python extension with maturin.\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    wheels = list(wheel_dir.glob("*.whl"))
    assert len(wheels) == 1, f"Expected one wheel from maturin, found: {wheels}"

    install = subprocess.run(
        [sys.executable, "-m", "pip", "install", "--no-deps", "--target", str(install_dir), str(wheels[0])],
        capture_output=True,
        text=True,
    )
    assert install.returncode == 0, (
        "Failed to install the freshly built extension.\n"
        f"stdout:\n{install.stdout}\nstderr:\n{install.stderr}"
    )
    return install_dir


def test_results_file_exists_and_passed():
    assert RESULTS_PATH.exists(), f"File {RESULTS_PATH} does not exist."
    content = RESULTS_PATH.read_text()
    assert "3 passed" in content, (
        "Test results do not indicate that 3 tests passed. Make sure to run pytest "
        "and save the output to test_results.txt."
    )


def test_rust_code_fixed():
    assert LIB_PATH.exists(), f"File {LIB_PATH} does not exist."
    content = LIB_PATH.read_text()
    assert re.search(r'"-"\s*=>\s*a\s*-\s*b', content), (
        "Subtraction bug in lib.rs not fixed. Expected 'a - b'."
    )
    assert re.search(r'"/"\s*=>\s*a\s*/\s*b', content), (
        "Division bug in lib.rs not fixed. Expected 'a / b'."
    )


def test_rust_compiles():
    assert PROJECT_DIR.is_dir(), f"Directory {PROJECT_DIR} does not exist."
    result = subprocess.run(
        ["cargo", "check"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        "Rust code failed to compile (cargo check returned non-zero).\n"
        f"Stderr:\n{result.stderr}"
    )


def test_freshly_built_extension_behavior(built_extension):
    rng = random.Random(918273)
    cases = []
    expected = []

    for _ in range(20):
        a = rng.uniform(-100.0, 100.0)
        b = rng.uniform(-100.0, 100.0)
        if abs(b) < 0.25:
            b = 0.25 if b >= 0 else -0.25
        cases.extend([
            f"{a!r} {b!r} -",
            f"{a!r} {b!r} /",
            f"{a!r} {b!r} +",
            f"{a!r} {b!r} *",
        ])
        expected.extend([a - b, a / b, a + b, a * b])

        c = rng.uniform(0.5, 10.0)
        cases.append(f"{a!r} {b!r} - {c!r} /")
        expected.append((a - b) / c)

    probe = r'''
import importlib.machinery
import importlib.util
import json
import os
import sys

install_dir = os.path.realpath(sys.argv[1])
sys.path.insert(0, install_dir)
spec = importlib.util.find_spec("rpn_eval")
assert spec is not None and spec.origin, "rpn_eval could not be imported"
origin = os.path.realpath(spec.origin)
assert os.path.commonpath([origin, install_dir]) == install_dir, origin
assert any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), origin
from rpn_eval import evaluate_rpn
expressions = json.loads(sys.argv[2])
print(json.dumps([evaluate_rpn(expr) for expr in expressions]))
'''
    run = subprocess.run(
        [sys.executable, "-I", "-c", probe, str(built_extension), json.dumps(cases)],
        cwd="/tmp",
        capture_output=True,
        text=True,
    )
    assert run.returncode == 0, (
        "The freshly built native extension could not be imported or executed.\n"
        f"stdout:\n{run.stdout}\nstderr:\n{run.stderr}"
    )
    actual = json.loads(run.stdout)
    assert len(actual) == len(expected)
    for expression, got, want in zip(cases, actual, expected):
        tolerance = 1e-9 * max(1.0, abs(want))
        assert abs(got - want) <= tolerance, (
            f"evaluate_rpn({expression!r}) returned {got}, expected {want}"
        )


def test_requested_property_suite_really_passes(built_extension):
    assert TEST_PATH.exists(), f"File {TEST_PATH} does not exist."
    env = os.environ.copy()
    env["PYTHONPATH"] = str(built_extension)
    result = subprocess.run(
        [sys.executable, "-m", "pytest", str(TEST_PATH), "--import-mode=importlib", "-q"],
        cwd="/tmp",
        env=env,
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, f"Property-based test suite failed.\n{output}"
    assert "3 passed" in output, f"Expected all three property tests to run and pass.\n{output}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
