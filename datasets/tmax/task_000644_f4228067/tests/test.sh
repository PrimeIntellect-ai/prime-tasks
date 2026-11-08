#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import sys
import pytest

sys.path.insert(0, "/home/user/math_api")


def encode_query(value):
    return bytes(byte ^ 0x42 for byte in value.encode("ascii")).hex()


def reference_poly(coeffs, x):
    return sum(c * (x ** i) for i, c in enumerate(coeffs))


def reference_derivative(coeffs, x):
    return sum(i * coeffs[i] * (x ** (i - 1)) for i in range(1, len(coeffs)))


def reference_newton(coeffs, guess):
    x = guess
    for _ in range(100):
        fx = reference_poly(coeffs, x)
        if abs(fx) < 1e-7:
            return x
        dfx = reference_derivative(coeffs, x)
        if dfx == 0:
            break
        x -= fx / dfx
    return x


def test_result_file():
    """Verify that result.txt exists and contains the correct rounded root."""
    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"{result_path} does not exist. Did you save the output?"

    with open(result_path, "r") as f:
        val = f.read().strip()

    assert val == "1.492043", f"Expected '1.492043' in result.txt, got '{val}'"


def test_decoder_fixed():
    """Verify that decoder.py correctly decodes a hex string to ascii after XORing bytes."""
    try:
        from decoder import decode_query
    except ImportError:
        pytest.fail("Could not import decode_query from decoder.py")

    test_hex = "12626e276c70227222726c7122726c7322727c622562732c22"
    expected = "P -10.0 0.0 3.0 1.0 | G 1.0"

    try:
        result = decode_query(test_hex)
    except Exception as e:
        pytest.fail(f"decode_query raised an exception: {e}")

    assert result == expected, f"Expected decode_query to return '{expected}', but got '{result}'"


def test_decoder_generated_inputs():
    from decoder import decode_query

    rng = random.SystemRandom()
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .|+-"
    for _ in range(20):
        expected = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 80)))
        assert decode_query(encode_query(expected)) == expected


def test_parser_fixed():
    """Verify that parser.py correctly handles negative signs and spaces."""
    try:
        from parser import parse_query
    except ImportError:
        pytest.fail("Could not import parse_query from parser.py")

    query_str = "P -10.0 0.0 3.0 1.0 | G 1.0"
    expected_coeffs = [-10.0, 0.0, 3.0, 1.0]
    expected_guess = 1.0

    try:
        coeffs, guess = parse_query(query_str)
    except Exception as e:
        pytest.fail(f"parse_query raised an exception: {e}")

    assert coeffs == expected_coeffs, f"Expected coefficients {expected_coeffs}, got {coeffs}"
    assert guess == expected_guess, f"Expected guess {expected_guess}, got {guess}"


def test_parser_generated_inputs_and_spacing():
    from parser import parse_query

    rng = random.SystemRandom()
    for _ in range(20):
        values = [rng.randint(-5000, 5000) / 100.0 for _ in range(rng.randint(1, 8))]
        values[0] = -abs(values[0] or 1.0)
        guess = rng.randint(-5000, 5000) / 100.0
        coeff_tokens = [f"{value:.2f}" for value in values]
        query = (
            "P" + " " * rng.randint(1, 5)
            + (" " * rng.randint(1, 5)).join(coeff_tokens)
            + " " * rng.randint(1, 5) + "|"
            + " " * rng.randint(1, 5) + "G"
            + " " * rng.randint(1, 5) + f"{guess:.2f}"
        )
        coeffs, parsed_guess = parse_query(query)
        assert coeffs == [float(token) for token in coeff_tokens]
        assert parsed_guess == float(f"{guess:.2f}")


def test_solver_fixed():
    """Verify that solver.py correctly computes the derivative and root."""
    try:
        from solver import evaluate_derivative, newton_root
    except ImportError:
        pytest.fail("Could not import evaluate_derivative and newton_root from solver.py")

    coeffs = [-10.0, 0.0, 3.0, 1.0]

    try:
        dfx = evaluate_derivative(coeffs, 1.0)
    except Exception as e:
        pytest.fail(f"evaluate_derivative raised an exception: {e}")

    assert abs(dfx - 9.0) < 1e-9, f"Expected derivative at x=1.0 to be 9.0, got {dfx}"

    try:
        root = newton_root(coeffs, 1.0)
    except Exception as e:
        pytest.fail(f"newton_root raised an exception: {e}")

    expected_root = 1.492043
    assert abs(root - expected_root) < 1e-5, f"Expected root near {expected_root}, got {root}"


def test_solver_generated_polynomials():
    from solver import evaluate_poly, evaluate_derivative, newton_root

    rng = random.SystemRandom()

    for _ in range(25):
        coeffs = [rng.uniform(-8.0, 8.0) for _ in range(rng.randint(2, 8))]
        x = rng.uniform(-2.0, 2.0)
        assert math.isclose(evaluate_poly(coeffs, x), reference_poly(coeffs, x), rel_tol=1e-11, abs_tol=1e-11)
        assert math.isclose(evaluate_derivative(coeffs, x), reference_derivative(coeffs, x), rel_tol=1e-11, abs_tol=1e-11)

    checked = 0
    while checked < 15:
        degree = rng.randint(2, 6)
        target = rng.uniform(-2.5, 2.5)
        coeffs = [0.0] + [rng.uniform(-3.0, 3.0) for _ in range(degree)]
        if abs(reference_derivative(coeffs, target)) < 0.75:
            continue
        coeffs[0] = -sum(coeffs[i] * target ** i for i in range(1, len(coeffs)))
        guess = target + rng.uniform(-0.01, 0.01)
        expected = reference_newton(coeffs, guess)
        actual = newton_root(coeffs, guess)
        assert math.isfinite(actual)
        assert abs(reference_poly(coeffs, actual)) < 1.1e-7
        assert abs(actual - expected) < 1e-6
        checked += 1


def test_main_executes_complete_pipeline():
    supplied = "12626e70227222726c7122726c7322727c622562732c22"
    # Preserve the exact supplied-query execution check using the instruction's value.
    supplied = "12626e276c70227222726c7122726c7322727c622562732c22"
    proc = subprocess.run(
        [sys.executable, "/home/user/math_api/main.py", supplied],
        cwd="/home/user/math_api", text=True, capture_output=True, timeout=10
    )
    assert proc.returncode == 0, proc.stderr
    assert abs(float(proc.stdout.strip()) - 1.492043) < 1e-5

    rng = random.SystemRandom()
    target = rng.uniform(0.7, 2.5)
    coeffs = [-(target ** 2), 0.0, 1.0]
    guess = rng.uniform(0.5, 3.0)
    query = "P " + "  ".join(f"{c:.12g}" for c in coeffs) + "   |  G   " + f"{guess:.12g}"
    encoded = encode_query(query)
    expected = reference_newton([float(f"{c:.12g}") for c in coeffs], float(f"{guess:.12g}"))
    proc = subprocess.run(
        [sys.executable, "/home/user/math_api/main.py", encoded],
        cwd="/home/user/math_api", text=True, capture_output=True, timeout=10
    )
    assert proc.returncode == 0, proc.stderr
    actual = float(proc.stdout.strip())
    assert abs(actual - expected) < 1e-6
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
