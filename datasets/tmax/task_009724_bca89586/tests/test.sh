#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/fixed_calc"
SOURCE = "/home/user/risk_engine/calc.cpp"
SOLUTION = "/home/user/solution.txt"


def expected_output(portfolio_id):
    prices = [10.5, 12.0, 11.5, 15.0, 14.5]
    if portfolio_id == 9942:
        prices.append(20.0)

    min_p = 10.0
    max_p = 20.0
    num_buckets = 5
    bucket_size = (max_p - min_p) / num_buckets
    histogram = [0] * num_buckets

    for price in prices:
        bucket = int((price - min_p) / bucket_size)
        bucket = max(0, min(bucket, num_buckets - 1))
        histogram[bucket] += 1

    score = sum(count * (index + 1) for index, count in enumerate(histogram))
    return f"Risk Score: {score}"


def run_calc(path, portfolio_id):
    try:
        result = subprocess.run(
            [path, str(portfolio_id)],
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Execution of {path} for portfolio {portfolio_id} failed: {exc.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {path} for portfolio {portfolio_id} timed out")
    return result.stdout.strip()


def test_fixed_calc_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "fixed_calc must be a compiled native executable, not a script."


def test_solution_txt_content():
    assert os.path.isfile(SOLUTION), f"Solution file {SOLUTION} does not exist."
    with open(SOLUTION, "r") as solution:
        content = solution.read().strip()
    assert content == "Risk Score: 15", f"Expected 'Risk Score: 15' in {SOLUTION}, but got '{content}'."


def test_fixed_calc_execution():
    output = run_calc(EXECUTABLE, 9942)
    assert output == "Risk Score: 15", f"Expected executable to output 'Risk Score: 15', but got '{output}'."


def test_recovered_source_contains_bucket_fix():
    assert os.path.isfile(SOURCE), f"Recovered source file {SOURCE} does not exist."
    with open(SOURCE, "r") as source_file:
        source = source_file.read()

    # Ignore comments so merely describing the missing fix cannot satisfy this check.
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)

    assert re.search(r"vector\s*<\s*double\s*>\s+prices", code), "Recovered price-processing code is missing."
    assert re.search(r"vector\s*<\s*int\s*>\s+histogram", code), "Recovered histogram code is missing."
    assert re.search(r"histogram\s*\.\s*at\s*\(\s*bucket\s*\)", code), "Recovered histogram update is missing."

    direct_clamp = re.search(
        r"if\s*\(\s*bucket\s*>=\s*num_buckets\s*\)\s*\{?\s*bucket\s*=\s*num_buckets\s*-\s*1\s*;",
        code,
    )
    equivalent_clamp = re.search(
        r"if\s*\(\s*bucket\s*>\s*num_buckets\s*-\s*1\s*\)\s*\{?\s*bucket\s*=\s*num_buckets\s*-\s*1\s*;",
        code,
    )
    min_clamp = re.search(
        r"bucket\s*=\s*(?:std\s*::\s*)?min\s*\(\s*bucket\s*,\s*num_buckets\s*-\s*1\s*\)\s*;",
        code,
    )
    assert direct_clamp or equivalent_clamp or min_clamp, "The upper bucket index is not clamped to num_buckets - 1."


def test_source_compiles_and_both_binaries_handle_derived_cases():
    build_dir = tempfile.mkdtemp(prefix="verify_calc_")
    rebuilt = os.path.join(build_dir, "calc")
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", rebuilt],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, f"Recovered calc.cpp does not compile:\n{compile_result.stderr}"

    rng = random.SystemRandom()
    portfolio_ids = [9942, 0, -1, 1, 9941, 9943, 2147483647]
    while len(portfolio_ids) < 30:
        candidate = rng.randint(2, 2_000_000_000)
        if candidate not in portfolio_ids:
            portfolio_ids.append(candidate)

    for portfolio_id in portfolio_ids:
        expected = expected_output(portfolio_id)
        submitted_output = run_calc(EXECUTABLE, portfolio_id)
        rebuilt_output = run_calc(rebuilt, portfolio_id)
        assert submitted_output == expected, (
            f"fixed_calc produced {submitted_output!r} for portfolio {portfolio_id}; expected {expected!r}."
        )
        assert rebuilt_output == expected, (
            f"Recovered calc.cpp produced {rebuilt_output!r} for portfolio {portfolio_id}; expected {expected!r}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
