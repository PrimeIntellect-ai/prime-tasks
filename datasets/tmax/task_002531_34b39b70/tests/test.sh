#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import stat
import subprocess
import urllib.request

import pytest

ROOTS = ("/app", "/home/user")


def submitted_files(suffixes=None):
    for root in ROOTS:
        if not os.path.isdir(root):
            continue
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", "node_modules"}]
            for name in files:
                path = os.path.join(base, name)
                if suffixes is None or name.lower().endswith(suffixes):
                    yield path


def test_cpp_core_and_ocr_pipeline_exist():
    cpp_files = list(submitted_files((".cpp", ".cc", ".cxx")))
    assert cpp_files, "No submitted C++ source file was found under /app or /home/user"

    cpp_texts = []
    for path in cpp_files:
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                cpp_texts.append(f.read())
        except OSError:
            pass
    source = "\n".join(cpp_texts).lower()

    assert "#include" in source and ("vector" in source or "[50]" in source), \
        "C++ source does not contain a grid-based implementation"
    assert "target" in source and ("1e-4" in source or "0.0001" in source), \
        "C++ source does not show target handling and the required convergence tolerance"
    assert ("normal_distribution" in source or
            (("rand(" in source or "random" in source) and "log(" in source and
             ("cos(" in source or "sin(" in source))), \
        "C++ source does not contain a Gaussian proposal implementation"
    assert "exp(" in source and ("metropolis" in source or "accept" in source), \
        "C++ source does not contain Metropolis-Hastings acceptance logic"
    assert ("least" in source or "quadratic" in source or
            ("sumx" in source and "sumy" in source)), \
        "C++ source does not contain quadratic least-squares fitting logic"

    readable = []
    for path in submitted_files((".cpp", ".cc", ".cxx", ".h", ".hpp", ".py", ".sh")):
        try:
            if os.path.getsize(path) <= 2_000_000:
                with open(path, "r", encoding="utf-8", errors="ignore") as f:
                    readable.append(f.read().lower())
        except OSError:
            pass
    pipeline_text = "\n".join(readable)
    assert "tesseract" in pipeline_text and "heat_schematic.png" in pipeline_text, \
        "No submitted pipeline code invokes OCR on /app/heat_schematic.png"

    elf_executables = []
    for path in submitted_files():
        try:
            mode = os.stat(path).st_mode
            if not stat.S_ISREG(mode) or not os.access(path, os.X_OK):
                continue
            with open(path, "rb") as f:
                if f.read(4) == b"\x7fELF":
                    elf_executables.append(path)
        except OSError:
            pass
    assert elf_executables, "No compiled executable for the submitted C++ implementation was found"


def solve_poisson(Q, X=25, Y=30, size=50, tol=1e-4):
    grid = [[0.0 for _ in range(size)] for _ in range(size)]
    max_diff = tol + 1.0
    iters = 0
    while max_diff >= tol and iters < 10000:
        max_diff = 0.0
        for i in range(1, size - 1):
            for j in range(1, size - 1):
                old = grid[i][j]
                source = Q if (i == X and j == Y) else 0.0
                new = 0.25 * (grid[i + 1][j] + grid[i - 1][j] +
                              grid[i][j + 1] + grid[i][j - 1] + source)
                grid[i][j] = new
                max_diff = max(max_diff, abs(new - old))
        iters += 1
    return grid


def quadratic_fit(values):
    n = len(values)
    sx = sum(range(n))
    sx2 = sum(x * x for x in range(n))
    sx3 = sum(x ** 3 for x in range(n))
    sx4 = sum(x ** 4 for x in range(n))
    sy = sum(values)
    sxy = sum(x * values[x] for x in range(n))
    sx2y = sum(x * x * values[x] for x in range(n))

    matrix = [
        [sx4, sx3, sx2, sx2y],
        [sx3, sx2, sx, sxy],
        [sx2, sx, float(n), sy],
    ]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda row: abs(matrix[row][col]))
        matrix[col], matrix[pivot] = matrix[pivot], matrix[col]
        divisor = matrix[col][col]
        for k in range(col, 4):
            matrix[col][k] /= divisor
        for row in range(3):
            if row == col:
                continue
            factor = matrix[row][col]
            for k in range(col, 4):
                matrix[row][k] -= factor * matrix[col][k]
    return tuple(matrix[row][3] for row in range(3))


def request_target(target):
    url = f"http://127.0.0.1:8080/generate?target={target:.8f}"
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            status = response.status
            body = response.read().decode("utf-8")
    except Exception as exc:
        pytest.fail(f"Failed to call generator for target {target}: {exc}")
    assert status == 200, f"Expected HTTP 200, got {status}: {body}"
    try:
        data = json.loads(body)
    except Exception as exc:
        pytest.fail(f"Response is not valid JSON: {body!r} ({exc})")
    required = {"Q", "a", "b", "c"}
    assert required.issubset(data), f"JSON response is missing keys: {required - set(data)}"
    try:
        result = {key: float(data[key]) for key in required}
    except (TypeError, ValueError) as exc:
        pytest.fail(f"Response values must be numeric: {exc}")
    assert all(math.isfinite(value) for value in result.values()), "Response contains non-finite values"
    return result


def test_generator_on_unpredictable_targets_and_validate_fit():
    rng = random.SystemRandom()
    targets = [rng.uniform(22.0, 42.0), rng.uniform(57.0, 82.0), rng.uniform(96.0, 124.0)]
    results = []

    for target in targets:
        data = request_target(target)
        assert data["Q"] > 0.0, f"Positive target {target} produced non-positive Q={data['Q']}"
        assert data["a"] < 0.0, f"Expected a negative quadratic coefficient, got {data['a']}"

        grid = solve_poisson(data["Q"])
        peak = max(max(row) for row in grid)
        assert abs(peak - target) <= 0.5, \
            f"Q={data['Q']} produces peak {peak}, not within ±0.5 of target {target}"

        profile = [grid[x][30] for x in range(50)]
        expected = quadratic_fit(profile)
        for key, actual, wanted in zip(("a", "b", "c"),
                                       (data["a"], data["b"], data["c"]), expected):
            tolerance = max(0.03, 0.02 * abs(wanted))
            assert abs(actual - wanted) <= tolerance, \
                f"Incorrect fitted coefficient {key}: got {actual}, expected {wanted} (tol {tolerance})"
        results.append(data)

    assert len({round(item["Q"], 5) for item in results}) == len(results), \
        "Generator returned the same Q for distinct targets"


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
