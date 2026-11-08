#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

import pytest

PROJECT = Path("/home/user/math_extension")


def test_run_log_contents():
    log_path = "/home/user/run.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you run the evaluation steps?"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {log_path}, found {len(lines)}."
    assert lines[0] == "-999", f"Expected first line to be '-999' (lite mode), but got '{lines[0]}'."
    assert lines[1] == "5", f"Expected second line to be '5' (full mode), but got '{lines[1]}'."


def test_c_math_c_updated():
    c_path = "/home/user/math_extension/c_math.c"
    assert os.path.isfile(c_path), f"File {c_path} does not exist."

    with open(c_path, "r") as f:
        content = f.read()

    assert "PyModuleDef" in content, "c_math.c does not appear to use PyModuleDef for Python 3 migration."
    assert "PyModule_Create" in content, "c_math.c does not appear to use PyModule_Create for Python 3 migration."
    assert "PyLong_FromLong" in content, "c_math.c does not appear to use PyLong_FromLong for Python 3 migration."
    assert "LITE_MODE" in content, "c_math.c does not contain logic for LITE_MODE."


def test_setup_py_updated():
    setup_path = "/home/user/math_extension/setup.py"
    assert os.path.isfile(setup_path), f"File {setup_path} does not exist."

    with open(setup_path, "r") as f:
        content = f.read()

    assert "BUILD_MODE" in content, "setup.py does not check the BUILD_MODE environment variable."
    assert "LITE_MODE" in content, "setup.py does not appear to add LITE_MODE to compiler arguments."


def build_extension(mode, root):
    build_lib = root / "lib"
    build_temp = root / "temp"
    build_lib.mkdir(parents=True)
    build_temp.mkdir(parents=True)

    env = os.environ.copy()
    env["BUILD_MODE"] = mode
    proc = subprocess.run(
        [
            sys.executable,
            "setup.py",
            "build_ext",
            "--force",
            "--build-lib",
            str(build_lib),
            "--build-temp",
            str(build_temp),
        ],
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert proc.returncode == 0, f"BUILD_MODE={mode} build failed:\n{proc.stdout}"

    artifacts = [
        Path(p) for p in glob.glob(str(build_lib / "c_math*"))
        if Path(p).is_file() and str(p).endswith(tuple(importlib.machinery.EXTENSION_SUFFIXES))
    ]
    assert len(artifacts) == 1, (
        f"BUILD_MODE={mode} did not produce exactly one Python extension artifact; "
        f"found: {artifacts}\nBuild output:\n{proc.stdout}"
    )
    artifact = artifacts[0]
    assert artifact.read_bytes()[:4] == b"\x7fELF", f"Built artifact is not an ELF shared library: {artifact}"
    return artifact


def run_extension(artifact, expressions):
    probe = r'''
import importlib.machinery
import importlib.util
import json
import sys

artifact = sys.argv[1]
expressions = json.loads(sys.argv[2])
spec = importlib.util.spec_from_file_location("c_math", artifact)
assert spec is not None
assert isinstance(spec.loader, importlib.machinery.ExtensionFileLoader)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert callable(module.eval_expr)
results = [module.eval_expr(expr) for expr in expressions]
assert all(type(value) is int for value in results)
print(json.dumps(results))
'''
    env = os.environ.copy()
    env.pop("BUILD_MODE", None)
    env.pop("LITE_MODE", None)
    proc = subprocess.run(
        [sys.executable, "-c", probe, str(artifact.resolve()), json.dumps(expressions)],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, (
        f"Could not import or exercise extension {artifact}:\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    try:
        return json.loads(proc.stdout.strip())
    except json.JSONDecodeError as exc:
        pytest.fail(f"Extension probe returned invalid output: {proc.stdout!r} ({exc})")


def c_div(a, b):
    quotient = abs(a) // abs(b)
    return -quotient if (a < 0) != (b < 0) else quotient


def test_compiled_extension_in_lite_and_full_modes(tmp_path):
    lite_artifact = build_extension("lite", tmp_path / "lite")
    full_artifact = build_extension("full", tmp_path / "full")

    a = secrets.randbelow(1801) - 900
    b = secrets.randbelow(97) + 2
    if secrets.randbelow(2):
        b = -b
    q = secrets.randbelow(101) - 50
    divisible_a = q * b

    expressions = [
        "/ 10 2",
        f"/ {a} {b}",
        f"/ {divisible_a} {b}",
        f"+ {a} {b}",
        f"- {a} {b}",
        f"* {a} {b}",
    ]

    lite_results = run_extension(lite_artifact, expressions)
    full_results = run_extension(full_artifact, expressions)

    assert lite_results == [-999, -999, -999, a + b, a - b, a * b], (
        f"Lite build produced incorrect results: {lite_results}"
    )
    assert full_results == [5, c_div(a, b), q, a + b, a - b, a * b], (
        f"Full build produced incorrect results: {full_results}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
