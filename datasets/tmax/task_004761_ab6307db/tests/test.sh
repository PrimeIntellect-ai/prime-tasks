#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import pytest

SOURCE_PATH = "/home/user/primer_opt/src/main.rs"


def strip_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)
    return source


def function_body(source, name):
    match = re.search(r"\bfn\s+" + re.escape(name) + r"\b[^\{]*\{", source)
    assert match, f"Missing required function {name}."
    start = match.end() - 1
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:pos]
    pytest.fail(f"Could not parse function {name}.")


def compact(text):
    return re.sub(r"\s+", "", text)


def test_rust_source_contains_required_damping():
    assert os.path.isfile(SOURCE_PATH), "Rust source file is missing."
    with open(SOURCE_PATH, "r") as f:
        source = strip_comments(f.read())

    expected_residual = """
        let mut r = DVector::zeros(params.len());
        for i in 0..params.len() {
            r[i] = params[i].powi(2) - 2.0;
        }
        r
    """
    expected_jacobian = """
        let mut j = DMatrix::zeros(params.len(), params.len());
        for i in 0..params.len() {
            j[(i, i)] = 2.0 * params[i];
        }
        let n = params.len();
        for c in 0..n {
            j[(n-1, c)] = 1e-12;
        }
        j
    """
    assert compact(function_body(source, "compute_residual")) == compact(expected_residual), \
        "The objective/residual calculation must not be changed."
    assert compact(function_body(source, "compute_jacobian")) == compact(expected_jacobian), \
        "The Jacobian calculation must not be changed."

    product = re.search(r"let\s+(?:mut\s+)?j_t_j\s*=\s*&j_t\s*\*\s*&j\s*;", source)
    assert product, "The expected J^T J construction is missing."
    solve = re.search(r"\.cholesky\s*\(", source[product.end():])
    assert solve, "The nalgebra Cholesky solve is missing."
    region = source[product.end():product.end() + solve.end()]

    lambda_re = re.compile(r"(?<![\w.])(?:1(?:\.0*)?[eE]-3|0\.001(?:0*)?)(?:_?f(?:32|64))?(?![\w.])")
    damping_var = None
    for statement in region.split(";"):
        if ("j_t_j" in statement and "DMatrix" in statement and
                re.search(r"\bidentity\s*\(", statement) and
                "+" in statement and lambda_re.search(statement)):
            declaration = re.match(r"\s*let\s+(?:mut\s+)?([A-Za-z_]\w*)\s*=", statement)
            if declaration:
                damping_var = declaration.group(1)
            elif re.search(r"\bj_t_j\s*\+=", statement):
                damping_var = "j_t_j"
            break

    assert damping_var is not None, \
        "Add DMatrix::identity(...) * 1e-3 to J^T J before factorization."
    assert re.search(r"\b" + re.escape(damping_var) + r"\s*\.\s*cholesky\s*\(", region), \
        "The matrix containing the 1e-3 diagonal damping must be the matrix factorized."


def solve3(a, b):
    a = [row[:] for row in a]
    b = b[:]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda row: abs(a[row][col]))
        a[col], a[pivot] = a[pivot], a[col]
        b[col], b[pivot] = b[pivot], b[col]
        for row in range(col + 1, 3):
            factor = a[row][col] / a[col][col]
            for k in range(col, 3):
                a[row][k] -= factor * a[col][k]
            b[row] -= factor * b[col]
    x = [0.0, 0.0, 0.0]
    for row in range(2, -1, -1):
        x[row] = (b[row] - sum(a[row][k] * x[k] for k in range(row + 1, 3))) / a[row][row]
    return x


def independently_calculated_result():
    params = [1.5, 0.5, 1.0]
    eps = 1e-12
    for _ in range(10):
        residual = [x * x - 2.0 for x in params]
        j = [[2.0 * params[0], 0.0, 0.0],
             [0.0, 2.0 * params[1], 0.0],
             [eps, eps, eps]]
        a = [[sum(j[k][row] * j[k][col] for k in range(3)) + (0.001 if row == col else 0.0)
              for col in range(3)] for row in range(3)]
        b = [sum(j[k][row] * residual[k] for k in range(3)) for row in range(3)]
        delta = solve3(a, b)
        params = [params[i] - delta[i] for i in range(3)]
    score = math.sqrt(sum((x * x - 2.0) ** 2 for x in params))
    return params, score


def test_json_output_exists_and_valid():
    json_path = "/home/user/output/optimized_primers.json"
    assert os.path.isfile(json_path), f"Output JSON file {json_path} is missing. The Rust application may not have run successfully."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert isinstance(data, list), "JSON output should be a list of results."
    assert len(data) > 0, "JSON output list is empty."

    for i, item in enumerate(data):
        assert "sequence_id" in item, f"Item at index {i} is missing 'sequence_id'."
        assert "params" in item, f"Item at index {i} is missing 'params'."
        assert "final_score" in item, f"Item at index {i} is missing 'final_score'."
        assert isinstance(item["final_score"], (int, float)), f"'final_score' at index {i} must be a number."
        assert not math.isnan(item["final_score"]), f"'final_score' at index {i} is NaN, which means the numerical instability was not fixed."

    expected_params, expected_score = independently_calculated_result()
    assert len(data) == 3, "The application must produce one native result for each provided sequence."
    for i, item in enumerate(data):
        assert item["sequence_id"] == i
        assert isinstance(item["params"], list) and len(item["params"]) == 3
        assert all(isinstance(value, (int, float)) and math.isfinite(value) for value in item["params"])
        assert math.isfinite(item["final_score"])
        for actual, expected in zip(item["params"], expected_params):
            assert actual == pytest.approx(expected, rel=1e-8, abs=1e-8)
        assert item["final_score"] == pytest.approx(expected_score, rel=1e-8, abs=1e-8)


def test_average_score_output():
    json_path = "/home/user/output/optimized_primers.json"
    txt_path = "/home/user/output/average_score.txt"

    assert os.path.isfile(json_path), f"Output JSON file {json_path} is missing."
    assert os.path.isfile(txt_path), f"Output text file {txt_path} is missing. Did you write the script to calculate the average score?"

    with open(json_path, "r") as f:
        data = json.load(f)

    scores = [item["final_score"] for item in data]
    expected_avg = sum(scores) / len(scores)
    expected_avg_rounded = round(expected_avg, 3)

    with open(txt_path, "r") as f:
        txt_content = f.read().strip()

    try:
        actual_avg = float(txt_content)
    except ValueError:
        pytest.fail(f"Content of {txt_path} is not a valid float: '{txt_content}'")

    assert round(actual_avg, 3) == expected_avg_rounded, f"Expected average score (rounded to 3 decimal places) to be {expected_avg_rounded}, but got {actual_avg} in {txt_path}"
TEST_EOF

passed=0
rm -f /home/user/output/optimized_primers.json
if cd /home/user/primer_opt \
   && cargo build --release \
   && test -x /home/user/primer_opt/target/release/primer_opt \
   && /home/user/primer_opt/target/release/primer_opt /home/user/data/sequences.txt \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
    passed=1
fi

echo "$passed" > /logs/verifier/reward.txt
