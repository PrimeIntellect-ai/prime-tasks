#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import os
import subprocess

import numpy as np

SCRIPT = '/home/user/error_analysis.py'
SLOPE = '/home/user/slope.txt'
NS = (10**3, 10**4, 10**5, 10**6, 10**7)


def get_expected_slope():
    """Compute the expected result independently using the required arithmetic."""
    script = r'''
import numpy as np

Ns = [10**3, 10**4, 10**5, 10**6, 10**7]
E = []
for N in Ns:
    terms = (1.0 / np.arange(1, N+1, dtype=np.float32)).astype(np.float32)
    s_asc = np.float32(0.0)
    for t in terms:
        s_asc += t
    s_desc = np.float32(0.0)
    for t in reversed(terms):
        s_desc += t
    E.append(abs(float(s_asc) - float(s_desc)))

slope, _ = np.polyfit(np.log10(Ns), np.log10(E), 1)
print(f"{slope:.2f}")
'''
    result = subprocess.run(
        ['python3', '-c', script], capture_output=True, text=True,
        check=True, timeout=180
    )
    return result.stdout.strip()


class InstrumentAccumulations(ast.NodeTransformer):
    """Instrument scalar accumulator additions while preserving their semantics."""
    def __init__(self):
        self.instrumented = 0

    def helper_call(self, node, target_name, left, right):
        self.instrumented += 1
        label = f'{getattr(node, "lineno", 0)}:{getattr(node, "col_offset", 0)}'
        return ast.copy_location(ast.Call(
            func=ast.Name(id='__verifier_float32_add', ctx=ast.Load()),
            args=[ast.Constant(label), left, right], keywords=[]
        ), node)

    def visit_AugAssign(self, node):
        node.value = self.visit(node.value)
        if isinstance(node.op, ast.Add) and isinstance(node.target, ast.Name):
            target = node.target.id
            replacement = ast.Assign(
                targets=[node.target],
                value=self.helper_call(
                    node, target, ast.Name(id=target, ctx=ast.Load()), node.value
                )
            )
            return ast.copy_location(replacement, node)
        return node

    def _replace_accumulation(self, value, target, owner):
        # s = s + term
        if (isinstance(value, ast.BinOp) and isinstance(value.op, ast.Add)
                and isinstance(value.left, ast.Name)
                and value.left.id == target):
            return self.helper_call(owner, target, value.left, value.right)

        # s = numpy.add(s, term) or np.add(s, term)
        if (isinstance(value, ast.Call) and isinstance(value.func, ast.Attribute)
                and value.func.attr == 'add' and len(value.args) >= 2
                and isinstance(value.args[0], ast.Name)
                and value.args[0].id == target):
            return self.helper_call(owner, target, value.args[0], value.args[1])

        # Preserve an explicit cast, as in s = np.float32(s + term).
        if (isinstance(value, ast.Call) and len(value.args) == 1
                and ((isinstance(value.func, ast.Attribute) and value.func.attr == 'float32')
                     or (isinstance(value.func, ast.Name) and value.func.id == 'float32'))):
            inner = self._replace_accumulation(value.args[0], target, owner)
            if inner is not value.args[0]:
                value.args[0] = inner
                return value
        return value

    def visit_Assign(self, node):
        node = self.generic_visit(node)
        if len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            target = node.targets[0].id
            node.value = self._replace_accumulation(node.value, target, node)
        return node


def term(i):
    return np.float32(np.float32(1.0) / np.float32(i))


class AdditionVerifier:
    """Validate every executed summation stream without storing all its terms."""
    def __init__(self):
        self.states = {}
        self.completed = []

    def _start(self, label, value):
        if value == term(1):
            self.states[label] = ['asc', None, 1]
            return
        matches = [n for n in NS if value == term(n)]
        assert len(matches) == 1, f'Unexpected first term {value!r} in loop {label}'
        self.states[label] = ['desc', matches[0], matches[0]]

    def _finish(self, label):
        direction, n, i = self.states[label]
        if direction == 'asc':
            assert i in NS, f'Ascending loop {label} stopped at unexpected N={i}'
            n = i
        else:
            assert i == 1, f'Descending loop {label} did not reach i=1'
        self.completed.append((n, direction))
        del self.states[label]

    def add(self, label, accumulator, value):
        assert type(accumulator) is np.float32, (
            f'Accumulator in loop {label} is {type(accumulator).__name__}, not numpy.float32'
        )
        assert type(value) is np.float32, (
            f'Term in loop {label} is {type(value).__name__}, not numpy.float32'
        )

        if label not in self.states:
            self._start(label, value)
        else:
            direction, n, i = self.states[label]
            if direction == 'asc':
                if i < NS[-1] and value == term(i + 1):
                    self.states[label][2] = i + 1
                else:
                    self._finish(label)
                    self._start(label, value)
            else:
                if i > 1 and value == term(i - 1):
                    self.states[label][2] = i - 1
                else:
                    self._finish(label)
                    self._start(label, value)

        return np.float32(accumulator + value)

    def finish(self):
        for label in list(self.states):
            self._finish(label)
        expected = collections.Counter(
            (n, direction) for n in NS for direction in ('asc', 'desc')
        )
        actual = collections.Counter(self.completed)
        assert actual == expected, (
            'The script did not execute exactly one ascending and one descending '
            f'naive float32 summation for every required N. Observed: {actual}'
        )


def execute_and_validate_script():
    with open(SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute):
                assert node.func.attr not in ('sum', 'fsum'), 'numpy.sum/math.fsum are forbidden'
            elif isinstance(node.func, ast.Name):
                assert node.func.id not in ('sum', 'fsum'), 'sum/fsum are not naive float32 loops'
        if isinstance(node, ast.Name):
            assert node.id != '__verifier_float32_add', 'Reserved verifier name used by script'

    transformer = InstrumentAccumulations()
    tree = transformer.visit(tree)
    ast.fix_missing_locations(tree)
    assert transformer.instrumented > 0, 'No iterative accumulator additions were found'

    if os.path.exists(SLOPE):
        os.remove(SLOPE)

    verifier = AdditionVerifier()
    globals_dict = {
        '__name__': '__main__',
        '__file__': SCRIPT,
        '__builtins__': __builtins__,
        '__verifier_float32_add': verifier.add,
    }
    old_cwd = os.getcwd()
    try:
        os.chdir('/home/user')
        exec(compile(tree, SCRIPT, 'exec'), globals_dict, globals_dict)
    finally:
        os.chdir(old_cwd)
    verifier.finish()


def test_script_exists():
    assert os.path.isfile(SCRIPT), '/home/user/error_analysis.py does not exist.'


def test_script_executes_required_float32_summations():
    execute_and_validate_script()


def test_slope_file_exists():
    assert os.path.isfile(SLOPE), '/home/user/slope.txt does not exist after executing the script.'


def test_slope_value():
    expected_val = get_expected_slope()
    with open(SLOPE, 'r', encoding='utf-8') as f:
        actual_val = f.read().strip()
    assert actual_val == expected_val, (
        f'Expected slope {expected_val}, but got {actual_val} in /home/user/slope.txt. '
        'Make sure you are using naive iterative float32 summation.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
