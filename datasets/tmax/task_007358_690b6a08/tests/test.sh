#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import subprocess
import tempfile
from decimal import Decimal
from fractions import Fraction

import pytest

FIXED = "/home/user/fixed_blackbox.py"
TEST_SH = "/home/user/test.sh"
RESULT_LOG = "/home/user/result.log"


def run_python(path):
    try:
        completed = subprocess.run(
            ["python3", path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Execution of {path} failed: {exc}")
    assert completed.stderr == "", f"{path} wrote unexpected stderr: {completed.stderr!r}"
    return completed.stdout


def test_fixed_blackbox_exists():
    """Check if the fixed Python script exists."""
    assert os.path.isfile(FIXED), "The file /home/user/fixed_blackbox.py is missing."
    assert not os.path.islink(FIXED), "fixed_blackbox.py must be a real Python source file, not a symlink."
    with open(FIXED, "r", encoding="utf-8") as handle:
        source = handle.read()
    assert source.strip(), "fixed_blackbox.py is empty."
    ast.parse(source, filename=FIXED)


def test_test_sh_exists_and_executable():
    """Check if test.sh exists and is executable."""
    assert os.path.isfile(TEST_SH), f"The file {TEST_SH} is missing."
    assert os.access(TEST_SH, os.X_OK), f"The file {TEST_SH} is not executable."


def test_test_sh_is_the_requested_reproducer():
    """Ensure test.sh runs the submitted program rather than fabricating result.log."""
    with open(TEST_SH, "r", encoding="utf-8") as handle:
        lines = []
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#") or line in {"set -e", "set -eu", "set -euo pipefail"}:
                continue
            lines.append(line)
    assert len(lines) == 1, "test.sh must contain only the requested execution/redirection command."
    assert re.fullmatch(
        r"(?:exec\s+)?python3\s+/home/user/fixed_blackbox\.py\s*(?:1?>|1?>\|)\s*/home/user/result\.log",
        lines[0],
    ), "test.sh must run python3 /home/user/fixed_blackbox.py and redirect stdout to result.log."


def test_fixed_blackbox_direct_execution():
    """Execute the submitted artifact independently of the submitted test script."""
    assert run_python(FIXED) == "1.0\n", "fixed_blackbox.py must print exactly one line containing 1.0."


class ReplaceProblemConstants(ast.NodeTransformer):
    def __init__(self, count, term):
        self.count = count
        self.term = term

    def visit_Constant(self, node):
        value = node.value
        if isinstance(value, int) and not isinstance(value, bool) and value == 10:
            return ast.copy_location(ast.Constant(self.count), node)
        if isinstance(value, float) and value == 0.1:
            return ast.copy_location(ast.Constant(float(self.term)), node)
        if isinstance(value, str):
            try:
                if Decimal(value) == Decimal("0.1"):
                    return ast.copy_location(ast.Constant(str(self.term)), node)
            except Exception:
                pass
        return node


def acceptable_exact_outputs(count, term):
    exact = Fraction(Decimal(str(term))) * count
    decimal_text = str(Decimal(exact.numerator) / Decimal(exact.denominator))
    float_text = repr(float(exact))
    return {decimal_text, float_text}


def test_algorithm_is_computed_not_hardcoded():
    """Exercise the recovered algorithm with derived, undisclosed parameter variations."""
    with open(FIXED, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=FIXED)

    variants = ((7, "0.25"), (11, "0.125"), (7, "0.2"))
    for count, term in variants:
        transformed = ReplaceProblemConstants(count, term).visit(ast.fix_missing_locations(tree))
        ast.fix_missing_locations(transformed)
        source = ast.unparse(transformed)
        fd, path = tempfile.mkstemp(prefix="fixed_variant_", suffix=".py")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(source)
                handle.write("\n")
            output = run_python(path)
        finally:
            os.unlink(path)

        assert output.endswith("\n") and output.count("\n") == 1, "The program must print one numerical line."
        value = output.strip()
        expected = acceptable_exact_outputs(count, term)
        assert value in expected, (
            f"The submitted program does not reproduce the blackbox's summation algorithm: "
            f"for {count} terms of {term}, got {value!r}, expected one of {sorted(expected)!r}."
        )


def test_test_sh_execution_and_result():
    """Run test.sh and verify the output in result.log."""
    if os.path.exists(RESULT_LOG):
        os.remove(RESULT_LOG)

    try:
        subprocess.run([TEST_SH], check=True, cwd="/home/user", capture_output=True, text=True, timeout=10)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Execution of {TEST_SH} failed: {exc}")

    assert os.path.isfile(RESULT_LOG), f"The file {RESULT_LOG} was not created by {TEST_SH}."
    with open(RESULT_LOG, "r") as handle:
        content = handle.read().strip()
    assert content == "1.0", f"Expected result.log to contain exactly '1.0', but found: {content!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
