#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import ast
import csv
import json
import math
import os
import re
import runpy
import secrets
import stat
import subprocess
import sys

HOME = "/home/user"
VENV_PYTHON = f"{HOME}/venv/bin/python"
VENV_PYTEST = f"{HOME}/venv/bin/pytest"
ETL = f"{HOME}/etl.py"
SOURCE = f"{HOME}/server_metrics.csv"
OUT_CSV = f"{HOME}/transformed_metrics.csv"
OUT_JSON = f"{HOME}/ttest_results.json"
TEST_ETL = f"{HOME}/test_etl.py"
PYTEST_LOG = f"{HOME}/pytest_output.txt"


def run(command, **kwargs):
    kwargs.setdefault("timeout", 120)
    result = subprocess.run(command, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{getattr(result, 'stdout', '')}"
        f"\nstderr:\n{getattr(result, 'stderr', '')}"
    )
    return result


def assert_regular_file(path):
    assert os.path.exists(path), f"{path} not found."
    assert stat.S_ISREG(os.stat(path, follow_symlinks=False).st_mode), \
        f"{path} must be a regular file."


def read_csv_output():
    with open(OUT_CSV, newline="") as handle:
        reader = csv.DictReader(handle)
        expected_fields = ["group", "count", "mean", "std", "ci_lower", "ci_upper"]
        assert reader.fieldnames == expected_fields, (
            f"Expected columns {expected_fields}, got {reader.fieldnames}"
        )
        rows = list(reader)
    assert len(rows) == 2, "Expected exactly 2 rows for 'control' and 'treatment'."
    data = {row["group"]: row for row in rows}
    assert set(data) == {"control", "treatment"}, \
        "Missing or unexpected groups in transformed CSV."
    return data


def check_original_outputs():
    assert_regular_file(OUT_CSV)
    data = read_csv_output()

    control = data["control"]
    assert int(control["count"]) == 500
    assert math.isclose(float(control["mean"]), 149.6853, abs_tol=0.001)
    assert math.isclose(float(control["std"]), 19.5593, abs_tol=0.001)
    assert math.isclose(float(control["ci_lower"]), 147.9667, abs_tol=0.001)
    assert math.isclose(float(control["ci_upper"]), 151.4038, abs_tol=0.001)

    treatment = data["treatment"]
    assert int(treatment["count"]) == 500
    assert math.isclose(float(treatment["mean"]), 145.4184, abs_tol=0.001)
    assert math.isclose(float(treatment["std"]), 21.6508, abs_tol=0.001)
    assert math.isclose(float(treatment["ci_lower"]), 143.5159, abs_tol=0.001)
    assert math.isclose(float(treatment["ci_upper"]), 147.3208, abs_tol=0.001)

    assert_regular_file(OUT_JSON)
    with open(OUT_JSON) as handle:
        result = json.load(handle)
    assert set(result) == {"t_stat", "p_value"}, \
        "ttest_results.json must contain exactly t_stat and p_value."
    assert type(result["t_stat"]) is float and type(result["p_value"]) is float, \
        "t_stat and p_value must be JSON floats."
    assert math.isclose(result["t_stat"], 3.273, rel_tol=0.01), \
        f"t_stat value {result['t_stat']} is incorrect."
    assert math.isclose(result["p_value"], 0.00109, rel_tol=0.01), \
        f"p_value value {result['p_value']} is incorrect."


def numeric_constant(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return float(node.value)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        value = numeric_constant(node.operand)
        return None if value is None else -value
    return None


def is_required_assert(node, variable, expected):
    if not isinstance(node, ast.Assert) or not isinstance(node.test, ast.Compare):
        return False
    comparison = node.test
    if len(comparison.ops) != 1 or not isinstance(comparison.ops[0], ast.Eq):
        return False
    if len(comparison.comparators) != 1:
        return False

    def is_round_call(candidate):
        return (
            isinstance(candidate, ast.Call)
            and isinstance(candidate.func, ast.Name)
            and candidate.func.id == "round"
            and len(candidate.args) == 2
            and isinstance(candidate.args[0], ast.Name)
            and candidate.args[0].id == variable
            and numeric_constant(candidate.args[1]) == 2.0
        )

    left = comparison.left
    right = comparison.comparators[0]
    return ((is_round_call(left) and numeric_constant(right) == expected) or
            (is_round_call(right) and numeric_constant(left) == expected))


def check_test_source_and_execution():
    assert_regular_file(TEST_ETL)
    with open(TEST_ETL) as handle:
        source = handle.read()
    assert "test_numerical_accuracy" in source, \
        "test_numerical_accuracy function not found in test_etl.py"

    tree = ast.parse(source, filename=TEST_ETL)
    functions = [node for node in tree.body
                 if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
                 and node.name == "test_numerical_accuracy"]
    assert len(functions) == 1, "Define exactly one test_numerical_accuracy function."
    function = functions[0]
    assert isinstance(function, ast.FunctionDef) and not function.args.args, \
        "test_numerical_accuracy must be a directly runnable pytest test."

    required_array = [10.0, 12.0, 14.0, 15.0, 11.0]
    found_array = False
    for node in ast.walk(function):
        if isinstance(node, (ast.List, ast.Tuple)) and len(node.elts) == 5:
            values = [numeric_constant(item) for item in node.elts]
            if values == required_array:
                found_array = True
                break
    assert found_array, "The required hardcoded dummy array is missing from the test."
    assert any(is_required_assert(node, "ci_lower", 9.95) for node in ast.walk(function)), \
        "Missing assertion round(ci_lower, 2) == 9.95."
    assert any(is_required_assert(node, "ci_upper", 14.85) for node in ast.walk(function)), \
        "Missing assertion round(ci_upper, 2) == 14.85."

    # Invoke the requested function directly so pytest hooks cannot fabricate a pass.
    direct_runner = (
        "import os, runpy, sys; "
        "os.chdir('/home/user'); sys.path.insert(0, '/home/user'); "
        "ns=runpy.run_path('/home/user/test_etl.py'); "
        "f=ns.get('test_numerical_accuracy'); "
        "assert callable(f); f()"
    )
    run([VENV_PYTHON, "-c", direct_runner], capture_output=True, text=True)

    environment = os.environ.copy()
    environment["PYTEST_DISABLE_PLUGIN_AUTOLOAD"] = "1"
    environment.pop("PYTEST_ADDOPTS", None)
    pytest_result = run(
        [VENV_PYTEST, "-q", "--confcutdir=/tmp", TEST_ETL + "::test_numerical_accuracy"],
        cwd="/tmp", env=environment, capture_output=True, text=True
    )
    combined = pytest_result.stdout + "\n" + pytest_result.stderr
    assert re.search(r"\b1 passed\b", combined), \
        f"The real pytest run did not report one passing test:\n{combined}"

    assert_regular_file(PYTEST_LOG)
    with open(PYTEST_LOG) as handle:
        saved_output = handle.read()
    assert "1 passed" in saved_output, \
        "pytest output does not show 1 passed test."


def betacf(a, b, x):
    max_iterations = 300
    epsilon = 3.0e-14
    floor = 1.0e-300
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < floor:
        d = floor
    d = 1.0 / d
    h = d
    for m in range(1, max_iterations + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < floor:
            d = floor
        c = 1.0 + aa / c
        if abs(c) < floor:
            c = floor
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < floor:
            d = floor
        c = 1.0 + aa / c
        if abs(c) < floor:
            c = floor
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < epsilon:
            return h
    raise AssertionError("Incomplete beta calculation did not converge")


def regularized_beta(a, b, x):
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    factor = math.exp(
        math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
        + a * math.log(x) + b * math.log1p(-x)
    )
    if x < (a + 1.0) / (a + b + 2.0):
        return factor * betacf(a, b, x) / a
    return 1.0 - factor * betacf(b, a, 1.0 - x) / b


def student_t_cdf(value, degrees):
    x = degrees / (degrees + value * value)
    tail = 0.5 * regularized_beta(degrees / 2.0, 0.5, x)
    return 1.0 - tail if value >= 0 else tail


def mean(values):
    return math.fsum(values) / len(values)


def sample_std(values):
    average = mean(values)
    return math.sqrt(math.fsum((x - average) ** 2 for x in values) / (len(values) - 1))


def check_dynamic_outputs(groups):
    data = read_csv_output()
    critical = {7: 2.4469118511449692, 9: 2.306004135204166}
    for group, values in groups.items():
        row = data[group]
        count = len(values)
        average = mean(values)
        std = sample_std(values)
        margin = critical[count] * std / math.sqrt(count)
        expected = {
            "count": count,
            "mean": round(average, 4),
            "std": round(std, 4),
            "ci_lower": round(average - margin, 4),
            "ci_upper": round(average + margin, 4),
        }
        assert int(row["count"]) == expected["count"]
        for field in ("mean", "std", "ci_lower", "ci_upper"):
            actual = float(row[field])
            assert math.isfinite(actual)
            assert math.isclose(actual, expected[field], rel_tol=0.0, abs_tol=5e-8), \
                f"Dynamic {group} {field}: expected {expected[field]}, got {actual}"

    with open(OUT_JSON) as handle:
        result = json.load(handle)
    assert set(result) == {"t_stat", "p_value"}
    assert type(result["t_stat"]) is float and type(result["p_value"]) is float

    first = groups["control"]
    second = groups["treatment"]
    n1, n2 = len(first), len(second)
    m1, m2 = mean(first), mean(second)
    s1, s2 = sample_std(first), sample_std(second)
    v1, v2 = s1 * s1 / n1, s2 * s2 / n2
    expected_t = (m1 - m2) / math.sqrt(v1 + v2)
    degrees = (v1 + v2) ** 2 / (v1 * v1 / (n1 - 1) + v2 * v2 / (n2 - 1))
    expected_p = 2.0 * min(student_t_cdf(expected_t, degrees),
                           1.0 - student_t_cdf(expected_t, degrees))
    assert math.isclose(result["t_stat"], expected_t, rel_tol=1e-10, abs_tol=1e-12)
    assert math.isclose(result["p_value"], expected_p, rel_tol=1e-9, abs_tol=1e-12)


def dynamic_etl_test():
    with open(SOURCE, "rb") as handle:
        original_source = handle.read()

    nonce = secrets.randbelow(1_000_000) / 100_000.0
    groups = {
        "control": [101.2 + nonce, 107.7, 98.4, 112.9, 105.3, 94.8, 109.1],
        "treatment": [89.6, 97.3 + nonce / 3.0, 93.1, 102.8, 95.5,
                      91.7, 99.4, 87.9, 104.2],
    }
    try:
        with open(SOURCE, "w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["group", "latency"])
            # Interleave and reverse values to catch positional hardcoding.
            maximum = max(map(len, groups.values()))
            for index in range(maximum):
                for group in ("treatment", "control"):
                    values = groups[group]
                    if index < len(values):
                        writer.writerow([group, values[-1 - index]])
        for path in (OUT_CSV, OUT_JSON):
            if os.path.lexists(path):
                os.unlink(path)
        run([VENV_PYTHON, ETL], cwd=HOME, capture_output=True, text=True)
        check_dynamic_outputs(groups)
    finally:
        with open(SOURCE, "wb") as handle:
            handle.write(original_source)
        for path in (OUT_CSV, OUT_JSON):
            if os.path.lexists(path):
                os.unlink(path)
        # Leave the requested final artifacts corresponding to the original input.
        run([VENV_PYTHON, ETL], cwd=HOME, capture_output=True, text=True)


def main():
    assert os.path.exists(VENV_PYTHON), "Virtual environment python binary not found."
    assert os.path.exists(VENV_PYTEST), "pytest not found in virtual environment."
    assert_regular_file(ETL)
    assert_regular_file(SOURCE)
    run([VENV_PYTHON, "-c", "import pandas, scipy, pytest"],
        capture_output=True, text=True)

    # Delete any prebuilt answers and require etl.py to regenerate them.
    for path in (OUT_CSV, OUT_JSON):
        if os.path.lexists(path):
            os.unlink(path)
    run([VENV_PYTHON, ETL], cwd=HOME, capture_output=True, text=True)
    check_original_outputs()
    check_test_source_and_execution()
    dynamic_etl_test()
    check_original_outputs()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
