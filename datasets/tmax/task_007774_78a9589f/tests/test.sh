#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import inspect
import os
import re
import secrets
import subprocess
import sys
import tempfile
from decimal import Decimal

import pytest


def test_final_total_file():
    path = "/home/user/final_total.txt"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content == "1060.95", f"Expected final_total.txt to contain '1060.95', but got '{content}'"


def test_aggregate_billing_uses_decimal():
    path = "/home/user/aggregate_billing.py"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, 'r') as f:
        content = f.read()

    assert "decimal" in content.lower(), "aggregate_billing.py does not appear to import or use the decimal module."


def test_test_billing_script_exists_and_passes():
    path = "/home/user/test_billing.py"
    assert os.path.isfile(path), f"File {path} is missing. You must create a regression test file."

    result = subprocess.run(["python3", path], capture_output=True, text=True)
    assert result.returncode == 0, f"Executing {path} failed with error:\n{result.stderr}\n{result.stdout}"

    with open(path, "r") as f:
        source = f.read()
    assert source.strip(), "test_billing.py must not be empty."
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError as exc:
        pytest.fail(f"test_billing.py is not valid Python: {exc}")

    imports_aggregate = any(
        (isinstance(node, ast.Import) and any(alias.name == "aggregate_billing" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "aggregate_billing")
        for node in ast.walk(tree)
    )
    assert imports_aggregate, "test_billing.py must import the fixed aggregation code."
    assert any(isinstance(node, ast.Assert) for node in ast.walk(tree)), \
        "test_billing.py must contain a regression assertion."
    assert any(
        (isinstance(node, ast.Name) and node.id == "aggregate_logs")
        or (isinstance(node, ast.Attribute) and node.attr == "aggregate_logs")
        for node in ast.walk(tree)
    ), "test_billing.py must exercise aggregate_logs."


def _load_module():
    sys.path.insert(0, "/home/user")
    try:
        import aggregate_billing
    except ImportError:
        pytest.fail("Could not import aggregate_billing.py")
    return aggregate_billing


def test_function_signatures_unchanged():
    aggregate_billing = _load_module()
    assert list(inspect.signature(aggregate_billing.parse_amount).parameters) == ["line"]
    assert list(inspect.signature(aggregate_billing.aggregate_logs).parameters) == ["filepath"]


def test_aggregate_billing_functionality():
    aggregate_billing = _load_module()

    test_log = "/tmp/test_billing_logs.txt"
    with open(test_log, "w") as f:
        f.write('txn_id=1 Amount="1,234.56"\n')
        f.write('txn_id=2 Amount="N/A"\n')
        f.write('txn_id=3 Amount=""\n')
        f.write('txn_id=4 Amount="0.10"\n')
        f.write('txn_id=5 Amount="0.20"\n')

    try:
        total = aggregate_billing.aggregate_logs(test_log)
        assert str(total) == "1234.86", f"Expected aggregate_logs to return Decimal('1234.86'), but got {total}"
        assert isinstance(total, Decimal), f"aggregate_logs must return Decimal, got {type(total).__name__}"
    finally:
        if os.path.exists(test_log):
            os.remove(test_log)


def test_decimal_parsing_and_randomized_aggregation():
    aggregate_billing = _load_module()

    invalid_lines = [
        'txn_id=x Amount="N/A"',
        'txn_id=x Amount=""',
        'txn_id=x Amount="not-a-number"',
        'txn_id=x no_amount_here',
    ]
    for line in invalid_lines:
        value = aggregate_billing.parse_amount(line)
        assert isinstance(value, Decimal), f"parse_amount must always return Decimal, got {type(value).__name__} for {line!r}"
        assert value == Decimal("0.0"), f"Invalid or missing amount should be zero for {line!r}, got {value}"

    for round_number in range(4):
        lines = []
        expected = Decimal("0")
        for index in range(12):
            whole = secrets.randbelow(9_000_000) + 1
            cents = secrets.randbelow(100)
            text = f"{whole:,}.{cents:02d}" if index % 2 == 0 else f"{whole}.{cents:02d}"
            lines.append(f'txn_id={round_number}-{index} Amount="{text}"\n')
            expected += Decimal(text.replace(",", ""))

        lines.extend([
            'txn_id=bad1 Amount="N/A"\n',
            'txn_id=bad2 Amount=""\n',
            'txn_id=bad3 Amount="invalid"\n',
            '\n',
        ])

        fd, path = tempfile.mkstemp(prefix="billing_case_", suffix=".txt")
        os.close(fd)
        try:
            with open(path, "w") as f:
                f.writelines(lines)
            total = aggregate_billing.aggregate_logs(path)
            assert isinstance(total, Decimal), f"aggregate_logs must return Decimal, got {type(total).__name__}"
            assert total == expected, f"Expected exact Decimal total {expected}, got {total}"
        finally:
            os.remove(path)


def test_exact_decimal_precision():
    aggregate_billing = _load_module()
    fd, path = tempfile.mkstemp(prefix="billing_precision_", suffix=".txt")
    os.close(fd)
    try:
        with open(path, "w") as f:
            for i in range(1000):
                f.write(f'txn_id={i} Amount="0.01"\n')
            f.write('txn_id=large Amount="9,999,999.99"\n')
        total = aggregate_billing.aggregate_logs(path)
        assert isinstance(total, Decimal)
        assert total == Decimal("10000009.99")
    finally:
        os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
