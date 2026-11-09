#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import sys
import importlib.util
import pytest

REPORT_PATH = "/home/user/fix_report.txt"
MODULE_PATH = "/home/user/app/risk_calc.py"
DUMP_PATH = "/home/user/crash_reports/memdump.dat"
TRANSACTIONS_PATH = "/home/user/app/transactions.json"


def load_risk_calc():
    assert os.path.exists(MODULE_PATH), f"File not found: {MODULE_PATH}"
    spec = importlib.util.spec_from_file_location("risk_calc", MODULE_PATH)
    risk_calc = importlib.util.module_from_spec(spec)
    sys.modules["risk_calc"] = risk_calc
    try:
        spec.loader.exec_module(risk_calc)
    except Exception as e:
        pytest.fail(f"Failed to load {MODULE_PATH}: {e}")
    assert hasattr(risk_calc, "calculate_risk"), "calculate_risk function is missing in risk_calc.py"
    assert callable(risk_calc.calculate_risk), "calculate_risk is not callable"
    return risk_calc


def specified_risk(v_list, w_list):
    numerator = sum(v * w for v, w in zip(v_list, w_list))
    sum_v_sq = sum(v ** 2 for v in v_list)
    sum_w_sq = sum(w ** 2 for w in w_list)
    return numerator / math.sqrt(abs(sum_v_sq - sum_w_sq))


def crashed_transaction_and_value():
    with open(DUMP_PATH, "rb") as f:
        dump = f.read()
    matches = re.findall(rb"CURRENT_PROCESSING_TXN:\s*(TXN-[A-Z0-9]{4}-[0-9]{4})", dump)
    assert matches, "No CURRENT_PROCESSING_TXN transaction ID found in memory dump"
    txn_id = matches[-1].decode("ascii")

    with open(TRANSACTIONS_PATH, "r") as f:
        transactions = json.load(f)
    assert txn_id in transactions, f"Crashed transaction {txn_id} is absent from transactions.json"
    txn = transactions[txn_id]
    return txn_id, specified_risk(txn["v_list"], txn["w_list"])


def test_fix_report_contents():
    assert os.path.exists(REPORT_PATH), f"Fix report not found at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        raw = f.read()

    # Preserve the original report assertions.
    nonblank_lines = [line.strip() for line in raw.splitlines() if line.strip()]
    assert len(nonblank_lines) >= 2, f"Expected at least 2 lines in {REPORT_PATH}, found {len(nonblank_lines)}"
    assert nonblank_lines[0] == "TXN-KLMN-9382", f"First line of fix_report.txt should be 'TXN-KLMN-9382', got '{nonblank_lines[0]}'"
    assert nonblank_lines[1] == "65.4330", f"Second line of fix_report.txt should be '65.4330', got '{nonblank_lines[1]}'"

    # Enforce exactly two lines, including rejection of extra blank lines.
    lines = raw.splitlines()
    assert len(lines) == 2, f"Expected exactly 2 lines in {REPORT_PATH}, found {len(lines)}"
    assert all(line == line.strip() and line for line in lines), "Report lines must be nonblank and contain no surrounding whitespace"

    txn_id, expected_value = crashed_transaction_and_value()
    assert lines[0] == txn_id, "Report transaction ID does not match the memory dump"
    assert re.fullmatch(r"-?[0-9]+\.[0-9]{4}", lines[1]), "Risk Index must be written with exactly 4 decimal places"
    assert lines[1] == f"{expected_value:.4f}", "Reported Risk Index does not match the transaction data and specified formula"


def test_risk_calc_fixed_for_crashed_transaction():
    risk_calc = load_risk_calc()
    v_list = [10, 20, 30]
    w_list = [15, 25, 35]

    try:
        result = risk_calc.calculate_risk(v_list, w_list)
    except ValueError as e:
        pytest.fail(f"calculate_risk raised ValueError (likely math.sqrt of negative number): {e}")
    except Exception as e:
        pytest.fail(f"calculate_risk raised an unexpected error: {e}")

    expected_result = 1700 / math.sqrt(675)
    assert math.isclose(result, expected_result, rel_tol=1e-5), f"calculate_risk returned {result}, expected approximately {expected_result}"


def test_risk_calc_matches_specification_on_varied_inputs():
    risk_calc = load_risk_calc()

    cases = [
        ([3, 4], [1, 2]),
        ([1, 2], [4, 6]),
        ([-5, 2, 7], [3, -4, 1]),
        ([9], [2]),
        ([2], [9]),
        ([0, 6, -8, 3], [5, 1, 2, -4]),
    ]

    rng = random.SystemRandom()
    while len(cases) < 30:
        length = rng.randint(1, 8)
        v_list = [rng.randint(-50, 50) for _ in range(length)]
        w_list = [rng.randint(-50, 50) for _ in range(length)]
        if sum(v * v for v in v_list) == sum(w * w for w in w_list):
            continue
        cases.append((v_list, w_list))

    for v_list, w_list in cases:
        expected = specified_risk(v_list, w_list)
        try:
            actual = risk_calc.calculate_risk(v_list, w_list)
        except Exception as e:
            pytest.fail(f"calculate_risk raised {type(e).__name__} for {v_list}, {w_list}: {e}")
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), "calculate_risk must return a number"
        assert math.isfinite(actual), f"calculate_risk returned a non-finite value for {v_list}, {w_list}"
        assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), (
            f"calculate_risk returned {actual} for {v_list}, {w_list}; expected {expected}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
