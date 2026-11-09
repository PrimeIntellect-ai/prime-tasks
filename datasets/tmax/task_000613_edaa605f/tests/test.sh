#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from pathlib import Path

ORACLE_PATH = "/app/version_evaluator"
AGENT_PATH = "/home/user/evaluator.py"
NUM_ITERATIONS = 1000
SEMVER = re.compile(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-((?:0|[1-9][0-9]*|[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$')

def parse_version(value):
    m = SEMVER.fullmatch(value)
    if not m:
        raise ValueError("invalid semantic version")
    return int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)

def compare_versions(left, right):
    a = parse_version(left)
    b = parse_version(right)
    if a[:3] != b[:3]:
        return -1 if a[:3] < b[:3] else 1
    pa, pb = a[3], b[3]
    if pa == pb:
        return 0
    if pa is None:
        return 1
    if pb is None:
        return -1
    aa, bb = pa.split('.'), pb.split('.')
    for x, y in zip(aa, bb):
        if x == y:
            continue
        xn, yn = x.isdigit(), y.isdigit()
        if xn and yn:
            return -1 if int(x) < int(y) else 1
        if xn != yn:
            return -1 if xn else 1
        return -1 if x < y else 1
    return (len(aa) > len(bb)) - (len(aa) < len(bb))

def apply_op(op, left, right):
    c = compare_versions(left, right)
    return {
        '=': c == 0, '==': c == 0, '!=': c != 0,
        '>': c > 0, '<': c < 0, '>=': c >= 0, '<=': c <= 0,
    }[op]

def generate_valid_semver():
    base = f"{random.randint(0,5)}.{random.randint(0,10)}.{random.randint(0,20)}"
    if random.random() < 0.3:
        base += '-' + random.choice(['alpha', 'beta', 'rc']) + str(random.randint(1,5))
    if random.random() < 0.2:
        base += '+build' + str(random.randint(100,999))
    return base

def generate_atom(target):
    op = random.choice(['=', '==', '!=', '>', '<', '>=', '<='])
    version = generate_valid_semver()
    return f"{op}{version}", apply_op(op, target, version)

def generate_expression(target, depth=0):
    if depth > 2 or random.random() < 0.4:
        return generate_atom(target)
    left, lv = generate_expression(target, depth + 1)
    right, rv = generate_expression(target, depth + 1)
    op = random.choice(['&&', '||'])
    text = f"{left} {op} {right}"
    if random.random() < 0.3:
        text = f"({text})"
    return text, (lv and rv if op == '&&' else lv or rv)

def run_cmd(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, timeout=2)
    except subprocess.TimeoutExpired:
        raise AssertionError(f"Command timed out: {cmd[0]}")

def assert_result(constraint, target, expected_output, expected_code):
    oracle = run_cmd([ORACLE_PATH, constraint, target])
    agent = run_cmd(['python3', AGENT_PATH, constraint, target])
    expected = (expected_output + '\n').encode()

    assert oracle.returncode == expected_code
    assert oracle.stdout == expected
    assert oracle.stderr == b''

    # Preserve the original oracle-equivalence assertions after validating that
    # the oracle itself agrees with independently derived SemVer expectations.
    assert agent.returncode == oracle.returncode, (
        f"Exit mismatch for {constraint!r}, {target!r}: "
        f"agent={agent.returncode}, oracle={oracle.returncode}"
    )
    assert agent.stdout == oracle.stdout, (
        f"Output mismatch for {constraint!r}, {target!r}: "
        f"agent={agent.stdout!r}, oracle={oracle.stdout!r}"
    )
    assert agent.stderr == b''

def test_artifact_and_argument_handling():
    path = Path(AGENT_PATH)
    assert path.is_file() and not path.is_symlink()
    compile(path.read_bytes(), AGENT_PATH, 'exec')
    assert os.path.isfile(ORACLE_PATH) and os.access(ORACLE_PATH, os.X_OK)

    for args in ([], ['>=1.0.0'], ['>=1.0.0', '1.0.0', 'extra']):
        result = run_cmd(['python3', AGENT_PATH] + args)
        assert result.returncode == 1
        assert result.stdout == b'INVALID\n'
        assert result.stderr == b''

def test_fixed_semantic_cases():
    cases = [
        ('>=1.2.3 && <2.0.0', '1.5.0', 'MATCH', 0),
        ('>=1.2.3 && <2.0.0', '2.0.0', 'NO_MATCH', 0),
        ('(>2.1.0 || ==2.0.0-rc.1) && !=2.1.5', '2.0.0-rc.1', 'MATCH', 0),
        ('==1.0.0', '1.0.0+build.7', 'MATCH', 0),
        ('>1.0.0-alpha.2', '1.0.0-alpha.10', 'MATCH', 0),
        ('==1.0.0 || ==2.0.0 && ==3.0.0', '1.0.0', 'MATCH', 0),
        ('1.2', '1.2.3', 'INVALID', 1),
        ('=>1.0.0', '1.0.0', 'INVALID', 1),
        ('(>1.0.0', '2.0.0', 'INVALID', 1),
        ('==1.0.0 && || ==2.0.0', '1.0.0', 'INVALID', 1),
        ('>=1.0.0', '1.0.0-', 'INVALID', 1),
        ('>=1.0.0', '01.0.0', 'INVALID', 1),
        ('>=1.0.0', '1.0.0-01', 'INVALID', 1),
    ]
    for case in cases:
        assert_result(*case)

def test_fuzz_equivalence_and_semantics():
    invalid_constraints = ['1.2', '=>1.0.0', '1.0.0-', '(>1.0.0', 'garbage string',
                           '==1.0.0 && || ==2.0.0', '>1.x.0', '', '()']
    invalid_targets = ['1.2', '1.0.0-', 'garbage', '1.x.0', '01.0.0', '1.0.0-01', '']
    random.seed(42)
    for _ in range(NUM_ITERATIONS):
        r = random.random()
        if r < 0.7:
            target = generate_valid_semver()
            constraint, matches = generate_expression(target)
            assert_result(constraint, target, 'MATCH' if matches else 'NO_MATCH', 0)
        elif r < 0.85:
            assert_result(random.choice(invalid_constraints), generate_valid_semver(), 'INVALID', 1)
        else:
            target = random.choice(invalid_targets)
            constraint, _ = generate_expression(generate_valid_semver())
            assert_result(constraint, target, 'INVALID', 1)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
