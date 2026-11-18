#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import sqlite3
import subprocess
from decimal import Decimal, getcontext

SCRIPT = '/home/user/gd_optimizer.sh'
SOLUTION = '/home/user/solution.txt'


def test_solution_file_exists():
    """Verify that the solution file exists."""
    assert os.path.isfile(SOLUTION), "/home/user/solution.txt is missing."


def test_solution_content():
    """Verify that the solution file contains the correctly rounded optimized value."""
    with open(SOLUTION, 'r') as f:
        content = f.read().strip()

    assert content == "2.00", f"Expected the solution file to contain exactly '2.00', but found '{content}'."


def test_gd_optimizer_modified():
    """Verify that decay is the final operation in the gradient-descent loop."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    with open(SCRIPT, 'r') as f:
        content = f.read()

    # Retain the original checks.
    assert "0.5" in content, "The script /home/user/gd_optimizer.sh does not appear to multiply the learning rate by 0.5 as requested."
    assert "bc -l" in content, "The script does not appear to use 'bc -l' for the math operations."

    syntax = subprocess.run(['bash', '-n', SCRIPT], text=True, capture_output=True)
    assert syntax.returncode == 0, f"Optimizer is not valid Bash: {syntax.stderr}"

    lines = content.splitlines()
    while_index = next((i for i, line in enumerate(lines)
                        if re.match(r'^\s*while\b', line)), None)
    assert while_index is not None, "The optimizer's while loop is missing."

    done_index = next((i for i in range(while_index + 1, len(lines))
                       if re.match(r'^\s*done\b', lines[i])), None)
    assert done_index is not None, "The optimizer's while loop has no closing done."

    body_lines = [line.strip() for line in lines[while_index + 1:done_index]
                  if line.strip() and not line.lstrip().startswith('#')]
    assert body_lines, "The optimizer's while loop is empty."
    last = body_lines[-1]

    assert re.match(r'^lr\s*=\s*"?\$\(', last), \
        "Learning-rate decay must be the final operation immediately before done."
    assert 'bc -l' in last and '0.5' in last and '*' in last, \
        "The final loop operation must multiply lr by 0.5 using bc -l."
    lr_ref = r'\$(?:lr|\{lr\})'
    assert (re.search(lr_ref + r'.*\*\s*0\.5', last) or
            re.search(r'0\.5\s*\*.*' + lr_ref, last)), \
        "The final loop operation must multiply the current lr by 0.5."


def find_failed_parameters():
    killed = []
    for path in glob.glob('/home/user/logs/*'):
        with open(path, 'r', errors='replace') as f:
            if 'KILLED' in f.read():
                killed.append(os.path.splitext(os.path.basename(path))[0])
    assert len(killed) == 1, f"Expected exactly one KILLED job, found {killed}."

    with sqlite3.connect('/home/user/jobs.db') as db:
        row = db.execute(
            'SELECT init_x, learning_rate FROM jobs WHERE job_name = ?',
            (killed[0],)
        ).fetchone()
    assert row is not None, f"No database parameters found for {killed[0]}."
    return str(row[0]), str(row[1])


def expected_result(init_x, learning_rate):
    getcontext().prec = 80
    x = Decimal(init_x)
    lr = Decimal(learning_rate)
    threshold = Decimal('0.0001')
    diff = Decimal('100')

    for _ in range(1000):
        if diff <= threshold:
            return x
        grad = Decimal(2) * x - Decimal(4)
        new_x = x - lr * grad
        diff = abs(new_x - x)
        x = new_x
        lr = lr * Decimal('0.5')
    raise AssertionError('Reference optimizer did not terminate.')


def run_optimizer(init_x, learning_rate):
    try:
        result = subprocess.run(
            [SCRIPT, init_x, learning_rate],
            text=True,
            capture_output=True,
            timeout=5
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(
            f"Optimizer timed out for init_x={init_x}, learning_rate={learning_rate}."
        )

    assert result.returncode == 0, \
        f"Optimizer failed for ({init_x}, {learning_rate}): {result.stderr}"
    output = result.stdout.strip()
    assert output, "Optimizer produced no output."
    try:
        return Decimal(output)
    except Exception:
        raise AssertionError(f"Optimizer output is not a single numeric value: {output!r}")


def test_optimizer_executes_with_decay_and_solution_matches():
    failed_init, failed_lr = find_failed_parameters()

    # Execute the requested failing job and independently derive its answer.
    failed_actual = run_optimizer(failed_init, failed_lr)
    failed_expected = expected_result(failed_init, failed_lr)
    assert abs(failed_actual - failed_expected) <= Decimal('0.00000001'), \
        f"Unexpected result for the failed job: {failed_actual} (expected {failed_expected})."

    with open(SOLUTION, 'r') as f:
        solution = f.read().strip()
    assert solution == format(failed_actual, '.2f'), \
        "solution.txt does not contain the optimizer's failed-job output rounded to two decimals."

    # Nontrivial derived cases distinguish real per-iteration decay from hardcoded output.
    for init_x, lr in [('10.0', '0.1'), ('-3.0', '0.2')]:
        actual = run_optimizer(init_x, lr)
        expected = expected_result(init_x, lr)
        assert abs(actual - expected) <= Decimal('0.00000001'), \
            f"Decay behavior is incorrect for ({init_x}, {lr}): got {actual}, expected {expected}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
