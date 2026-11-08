#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import secrets
import shutil
import subprocess
import sys

import pytest
from packaging.requirements import Requirement
from packaging.version import Version

SERVICE_DIR = "/home/user/service"
MATH_UTILS_PATH = os.path.join(SERVICE_DIR, "math_utils.py")
TEST_MATH_PATH = os.path.join(SERVICE_DIR, "test_math.py")
REQUIREMENTS_PATH = os.path.join(SERVICE_DIR, "requirements.txt")
RESOLUTION_LOG_PATH = "/home/user/resolution.log"


def load_module_from_path(module_name, file_path):
    spec = importlib.util.spec_from_file_location(module_name, file_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def expected_collatz_steps(n):
    steps = 0
    while n != 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        steps += 1
    return steps


def run_collatz_cases(values):
    worker = r'''
import importlib.util
import json
import sys
spec = importlib.util.spec_from_file_location("submitted_math_utils", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
results = []
for value in json.loads(sys.argv[2]):
    try:
        result = module.collatz_steps(value)
        results.append({"kind": "return", "value": result})
    except Exception as exc:
        results.append({"kind": "raise", "type": type(exc).__name__, "message": str(exc)})
print(json.dumps(results))
'''
    result = subprocess.run(
        [sys.executable, "-c", worker, MATH_UTILS_PATH, json.dumps(values)],
        capture_output=True,
        text=True,
        timeout=8,
    )
    assert result.returncode == 0, f"collatz_steps execution failed:\n{result.stdout}\n{result.stderr}"
    try:
        return json.loads(result.stdout)
    except Exception as exc:
        pytest.fail(f"Could not decode collatz_steps results: {exc}; output={result.stdout!r}")


def test_math_utils_logic():
    assert os.path.isfile(MATH_UTILS_PATH), f"{MATH_UTILS_PATH} does not exist."
    math_utils = load_module_from_path("math_utils", MATH_UTILS_PATH)
    assert hasattr(math_utils, "collatz_steps"), "collatz_steps function is missing."

    # Preserve the original explicit checks.
    assert math_utils.collatz_steps(10) == 6, "collatz_steps(10) should return 6."
    with pytest.raises(ValueError, match="positive"):
        math_utils.collatz_steps(0)
    with pytest.raises(ValueError):
        math_utils.collatz_steps(-5)

    rng = secrets.SystemRandom()
    positives = [1, 2, 3, 10, 27, 97] + rng.sample(range(4, 50000), 30)
    positive_results = run_collatz_cases(positives)
    assert len(positive_results) == len(positives)
    for n, observed in zip(positives, positive_results):
        assert observed == {"kind": "return", "value": expected_collatz_steps(n)}, (
            f"collatz_steps({n}) produced {observed!r}"
        )

    nonpositives = [0, -1, -2, -5, -17, -100] + [-rng.randint(101, 1000000) for _ in range(20)]
    invalid_results = run_collatz_cases(nonpositives)
    assert len(invalid_results) == len(nonpositives)
    for n, observed in zip(nonpositives, invalid_results):
        assert observed.get("kind") == "raise", f"collatz_steps({n}) did not raise"
        assert observed.get("type") == "ValueError", f"collatz_steps({n}) raised the wrong exception"
        assert observed.get("message") == "n must be positive", (
            f"collatz_steps({n}) used the wrong error message"
        )


def clear_python_cache():
    cache_dir = os.path.join(SERVICE_DIR, "__pycache__")
    if os.path.isdir(cache_dir):
        shutil.rmtree(cache_dir)


def run_agent_tests():
    clear_python_cache()
    return subprocess.run(
        [sys.executable, "-m", "pytest", TEST_MATH_PATH],
        cwd=SERVICE_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )


def test_regression_test_file():
    assert os.path.isfile(TEST_MATH_PATH), f"{TEST_MATH_PATH} does not exist."
    with open(TEST_MATH_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    assert "test_collatz_valid" in content, "test_collatz_valid() is missing in test_math.py."
    assert "test_collatz_invalid" in content, "test_collatz_invalid() is missing in test_math.py."
    assert "pytest" in content or "ValueError" in content, "test_math.py doesn't seem to use pytest features properly."

    result = run_agent_tests()
    assert result.returncode == 0, f"pytest failed on {TEST_MATH_PATH}:\n{result.stdout}\n{result.stderr}"

    with open(MATH_UTILS_PATH, "rb") as f:
        original = f.read()
    mutants = [
        b'def collatz_steps(n):\n    if n <= 0:\n        raise ValueError("n must be positive")\n    if n == 10:\n        return 7\n    return 0\n',
        b'def collatz_steps(n):\n    if n == 10:\n        return 6\n    if n == 0:\n        return 0\n    raise ValueError("n must be positive")\n',
    ]
    try:
        for mutant in mutants:
            with open(MATH_UTILS_PATH, "wb") as f:
                f.write(mutant)
            result = run_agent_tests()
            assert result.returncode != 0, (
                "test_math.py passed despite a deliberately broken collatz_steps implementation"
            )
    finally:
        with open(MATH_UTILS_PATH, "wb") as f:
            f.write(original)
        clear_python_cache()


def parsed_pinned_requirements():
    assert os.path.isfile(REQUIREMENTS_PATH), f"{REQUIREMENTS_PATH} does not exist."
    parsed = {}
    with open(REQUIREMENTS_PATH, "r", encoding="utf-8") as f:
        lines = f.readlines()
    for raw in lines:
        text = raw.strip()
        if not text or text.startswith("#"):
            continue
        try:
            req = Requirement(text)
        except Exception as exc:
            pytest.fail(f"Invalid dependency specification {text!r}: {exc}")
        name = req.name.lower()
        if name in ("flask", "werkzeug"):
            assert name not in parsed, f"Duplicate {req.name} requirements are not allowed"
            specs = list(req.specifier)
            assert len(specs) == 1 and specs[0].operator == "==" and "*" not in specs[0].version, (
                f"{req.name} must be pinned to an exact version"
            )
            parsed[name] = Version(specs[0].version)
    return parsed


def test_requirements_updated():
    parsed = parsed_pinned_requirements()
    assert "flask" in parsed, "requirements.txt must contain Flask"
    assert "werkzeug" in parsed, "requirements.txt must contain Werkzeug"

    flask_version = parsed["flask"]
    werkzeug_version = parsed["werkzeug"]
    assert not (flask_version == Version("2.0.1") and werkzeug_version == Version("2.2.2")), (
        "requirements.txt still contains the conflicting versions."
    )
    valid_pair = (
        flask_version == Version("2.0.1") and werkzeug_version < Version("2.1.0")
    ) or (
        flask_version == Version("2.2.2") and werkzeug_version >= Version("2.2.2")
    )
    assert valid_pair, (
        f"Unsupported or conflicting Flask/Werkzeug pair: Flask {flask_version}, Werkzeug {werkzeug_version}"
    )


def test_resolution_log():
    assert os.path.isfile(RESOLUTION_LOG_PATH), f"{RESOLUTION_LOG_PATH} does not exist."
    with open(RESOLUTION_LOG_PATH, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert len(lines) == 2, f"resolution.log must contain exactly two lines, found {len(lines)}."

    parsed = parsed_pinned_requirements()
    changed = []
    if parsed["flask"] != Version("2.0.1"):
        changed.append(f"Flask=={parsed['flask']}")
    if parsed["werkzeug"] != Version("2.2.2"):
        changed.append(f"Werkzeug=={parsed['werkzeug']}")
    assert lines[0] in changed, (
        "First line of resolution.log must be the exact package name and pinned version modified in requirements.txt"
    )
    assert lines[1] == "TESTS_PASSED", "Second line of resolution.log must be 'TESTS_PASSED'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
