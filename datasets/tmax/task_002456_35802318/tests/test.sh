#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import subprocess
from decimal import Decimal

REPO = "/home/user/analytics_repo"
PROCESS = os.path.join(REPO, "process.py")
TRANSACTIONS = os.path.join(REPO, "transactions.csv")
TOTAL = "/home/user/total.txt"


def run_process():
    result = subprocess.run(
        ["python3", PROCESS],
        cwd=REPO,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"process.py exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(TOTAL), "process.py did not create /home/user/total.txt"
    return open(TOTAL, "r").read().strip()


def test_key_file():
    key_path = "/home/user/key.txt"
    assert os.path.isfile(key_path), f"File {key_path} does not exist. Phase 1 incomplete."
    with open(key_path, "r") as f:
        content = f.read().strip()
    expected_key = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
    assert content == expected_key, f"Content of {key_path} is incorrect. Expected {expected_key}, got {content}."


def test_token_file():
    token_path = "/home/user/.hidden_token_file"
    assert os.path.isfile(token_path), f"File {token_path} does not exist. Phase 2 incomplete."
    with open(token_path, "r") as f:
        content = f.read().strip()
    expected_token = "TOKEN_OK"
    assert content == expected_token, f"Content of {token_path} is incorrect. Expected {expected_token}, got {content}."


def test_total_file():
    assert os.path.isfile(TOTAL), f"File {TOTAL} does not exist. Did you run the script?"
    with open(TOTAL, "r") as f:
        content = f.read().strip()
    expected_total = "Total: 110.95"
    assert content == expected_total, f"Content of {TOTAL} is incorrect. Expected '{expected_total}', got '{content}'. Ensure you fixed the precision bug and ran the script."


def test_process_py_uses_decimal():
    assert os.path.isfile(PROCESS), f"File {PROCESS} does not exist."
    with open(PROCESS, "r") as f:
        content = f.read()
    assert "decimal" in content or "Decimal" in content, "The process.py script does not appear to use the 'decimal' module as requested."

    tree = ast.parse(content, filename=PROCESS)
    imports_decimal = any(
        (isinstance(node, ast.Import) and any(alias.name == "decimal" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "decimal")
        for node in ast.walk(tree)
    )
    calls_decimal = any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Name) and node.func.id == "Decimal")
            or (
                isinstance(node.func, ast.Attribute)
                and node.func.attr == "Decimal"
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id == "decimal"
            )
        )
        for node in ast.walk(tree)
    )
    assert imports_decimal and calls_decimal, "process.py must import and call Decimal, not merely mention decimal in a comment or string."

    reference = subprocess.check_output(["git", "show", "HEAD:process.py"], cwd=REPO)
    with open(PROCESS, "rb") as f:
        submitted = f.read()
    assert submitted != reference, "process.py is still byte-identical to the shipped buggy implementation."


def test_process_executes_and_calculates_unseen_inputs():
    with open(TRANSACTIONS, "rb") as f:
        original_transactions = f.read()

    cases = []
    small_values = [f"{secrets.randbelow(10000) / 100:.2f}" for _ in range(17)]
    cases.append(small_values)

    # At this magnitude binary-float accumulation loses cents, while Decimal does not.
    large_values = ["100000000000000.00"]
    large_values.extend(f"0.{secrets.randbelow(99) + 1:02d}" for _ in range(41))
    cases.append(large_values)

    try:
        for values in cases:
            with open(TRANSACTIONS, "w") as f:
                f.write("\n".join(values) + "\n")
            if os.path.exists(TOTAL):
                os.remove(TOTAL)

            expected_amount = sum((Decimal(value) for value in values), Decimal("0"))
            expected = f"Total: {expected_amount:.2f}"
            actual = run_process()
            assert actual == expected, f"For verifier-generated transactions, expected {expected!r}, got {actual!r}."
    finally:
        with open(TRANSACTIONS, "wb") as f:
            f.write(original_transactions)
        # Leave the requested report in its final state and verify the restored data too.
        restored = run_process()
        assert restored == "Total: 110.95", f"Restored pipeline produced {restored!r} instead of 'Total: 110.95'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
