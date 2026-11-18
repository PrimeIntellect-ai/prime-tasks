#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import subprocess
from decimal import Decimal


def run_python(path, *args, cwd="/home/user"):
    return subprocess.run(
        ["python3", path, *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_ticket_output():
    path = "/home/user/ticket_4492_output.txt"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "alice,bob", f"Expected 'alice,bob' in {path}, but got '{content}'"

    result = run_python("/home/user/billing_query.py", "--target", "15.30")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == content, "The saved report does not match a fresh application run."


def test_billing_query_uses_decimal():
    path = "/home/user/billing_query.py"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "decimal" in content, f"Expected 'decimal' to be imported and used in {path}"

    tree = ast.parse(content, filename=path)
    imports_decimal = any(
        (isinstance(node, ast.Import) and any(alias.name == "decimal" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "decimal")
        for node in ast.walk(tree)
    )
    decimal_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and (
            isinstance(node.func, ast.Name) and node.func.id == "Decimal"
            or isinstance(node.func, ast.Attribute) and node.func.attr == "Decimal"
        )
    ]
    float_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "float"
    ]
    assert imports_decimal, "billing_query.py must import the decimal module."
    assert decimal_calls, "billing_query.py must actually construct Decimal values."
    assert not float_calls, "billing_query.py still performs standard float conversions."


def test_billing_query_exact_arithmetic_on_derived_cases():
    csv_path = "/home/user/transactions.csv"
    script = "/home/user/billing_query.py"
    with open(csv_path, "rb") as f:
        original = f.read()

    rows = [
        ("sum_user", "0.10"),
        ("sum_user", "0.20"),
        ("direct_user", "0.30"),
        ("near_user", "0.29"),
        ("ticket_user", "15.10"),
        ("ticket_user", "0.20"),
        ("other_user", "15.31"),
        ("negative_user", "-1.10"),
        ("negative_user", "0.80"),
    ]

    try:
        with open(csv_path, "w", newline="") as f:
            f.write("user_id,amount\n")
            for user, amount in rows:
                f.write(f"{user},{amount}\n")

        balances = {}
        for user, amount in rows:
            balances[user] = balances.get(user, Decimal("0")) + Decimal(amount)

        for target in ("0.30", "15.30", "-0.30", "15.31"):
            expected = ",".join(sorted(
                user for user, balance in balances.items() if balance == Decimal(target)
            ))
            result = run_python(script, "--target", target)
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == expected, (
                f"Incorrect result for target {target}: expected {expected!r}, "
                f"got {result.stdout.strip()!r}"
            )
    finally:
        with open(csv_path, "wb") as f:
            f.write(original)


def _expanded_expression(expr, assignments, seen=None):
    seen = set() if seen is None else set(seen)
    if isinstance(expr, ast.Name) and expr.id in assignments and expr.id not in seen:
        seen.add(expr.id)
        return _expanded_expression(assignments[expr.id], assignments, seen)
    if isinstance(expr, ast.BinOp):
        expr.left = _expanded_expression(expr.left, assignments, seen)
        expr.right = _expanded_expression(expr.right, assignments, seen)
    elif isinstance(expr, ast.Compare):
        expr.left = _expanded_expression(expr.left, assignments, seen)
        expr.comparators = [_expanded_expression(x, assignments, seen) for x in expr.comparators]
    return expr


def _numeric_leaves(expr):
    values = []
    for node in ast.walk(expr):
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)) and not isinstance(node.value, bool):
            values.append(float(node.value))
        elif (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "float"
            and len(node.args) == 1
            and isinstance(node.args[0], ast.Constant)
        ):
            try:
                values.append(float(node.args[0].value))
            except (TypeError, ValueError):
                pass
    return values


def test_mre_script():
    path = "/home/user/mre.py"
    assert os.path.isfile(path), f"File {path} is missing."

    result = run_python(path)
    assert result.returncode == 0, f"{path} failed to execute."
    output = result.stdout.strip()
    assert output == "False", f"Expected mre.py to output 'False', but got '{output}'"

    with open(path, "r") as f:
        tree = ast.parse(f.read(), filename=path)

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            assignments[node.targets[0].id] = node.value

    printed = []
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "print"
            and len(node.args) == 1
        ):
            printed.append(_expanded_expression(node.args[0], assignments))

    valid = False
    for expr in printed:
        if not isinstance(expr, ast.Compare) or not any(isinstance(op, ast.Eq) for op in expr.ops):
            continue
        add_nodes = [node for node in ast.walk(expr) if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add)]
        values = _numeric_leaves(expr)
        if add_nodes and all(any(abs(value - wanted) < 1e-12 for value in values) for wanted in (15.1, 0.2, 15.3)):
            valid = True
            break
    assert valid, "mre.py must print the equality comparison of float 15.10 + 0.20 against float 15.30."


def test_fuzz_log():
    script = "/home/user/fuzz_test.py"
    log = "/home/user/fuzz.log"
    assert os.path.isfile(script), f"File {script} is missing."

    if os.path.exists(log):
        os.remove(log)
    result = run_python(script)
    assert result.returncode == 0, f"{script} failed to execute: {result.stderr}"
    assert os.path.isfile(log), "fuzz_test.py did not create /home/user/fuzz.log."

    with open(log, "r") as f:
        content = f.read().strip()
    assert content == "FUZZ_OK", f"Expected 'FUZZ_OK' in {log}, but got '{content}'"

    with open(script, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=script)

    loops_1000 = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.For)
        and isinstance(node.iter, ast.Call)
        and isinstance(node.iter.func, ast.Name)
        and node.iter.func.id == "range"
        and len(node.iter.args) == 1
        and isinstance(node.iter.args[0], ast.Constant)
        and node.iter.args[0].value == 1000
    ]
    assert loops_1000, "fuzz_test.py must loop 1000 times."

    has_random_import = any(
        (isinstance(node, ast.Import) and any(alias.name == "random" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "random")
        for node in ast.walk(tree)
    )
    has_random_call = any(
        isinstance(node, ast.Call)
        and (
            isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "random"
            or isinstance(node.func, ast.Name)
            and node.func.id in {"random", "randint", "randrange", "uniform", "choice"}
        )
        for node in ast.walk(tree)
    )
    assert has_random_import and has_random_call, "fuzz_test.py must generate random test values."

    has_float_call = any(
        isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "float"
        for node in ast.walk(tree)
    )
    has_decimal_call = any(
        isinstance(node, ast.Call)
        and (
            isinstance(node.func, ast.Name) and node.func.id == "Decimal"
            or isinstance(node.func, ast.Attribute) and node.func.attr == "Decimal"
        )
        for node in ast.walk(tree)
    )
    has_add = any(isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add) for node in ast.walk(tree))
    has_equality = any(
        isinstance(node, ast.Compare) and any(isinstance(op, ast.Eq) for op in node.ops)
        for node in ast.walk(tree)
    )
    assert has_float_call and has_decimal_call and has_add and has_equality, (
        "fuzz_test.py must compare float and Decimal addition results."
    )

    zero_counters = {
        target.id
        for node in ast.walk(tree)
        if isinstance(node, ast.Assign)
        and isinstance(node.value, ast.Constant)
        and node.value.value == 0
        for target in node.targets
        if isinstance(target, ast.Name)
    }
    updated_counters = set()
    for loop in loops_1000:
        for node in ast.walk(loop):
            if isinstance(node, ast.AugAssign) and isinstance(node.target, ast.Name):
                updated_counters.add(node.target.id)
            elif isinstance(node, ast.Assign):
                for target in node.targets:
                    if isinstance(target, ast.Name) and isinstance(node.value, ast.BinOp):
                        updated_counters.add(target.id)
    assert len(zero_counters & updated_counters) >= 2, "fuzz_test.py must maintain float and Decimal match counts."

    guarded_success = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.If):
            continue
        test_has_1000 = any(isinstance(x, ast.Constant) and x.value == 1000 for x in ast.walk(node.test))
        body_has_success = any(isinstance(x, ast.Constant) and x.value == "FUZZ_OK" for stmt in node.body for x in ast.walk(stmt))
        if test_has_1000 and body_has_success:
            guarded_success = True
            break
    assert guarded_success, "FUZZ_OK must be conditional on the Decimal count reaching 1000."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
