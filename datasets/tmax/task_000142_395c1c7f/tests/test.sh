#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import re
import signal
import subprocess
import time
from pathlib import Path

SCRIPT = Path('/home/user/mc_volume.py')
PDB = Path('/home/user/molecule.pdb')
OUTPUT = Path('/home/user/volume_estimate.txt')


def _const(expr, values):
    if isinstance(expr, ast.Constant) and isinstance(expr.value, (int, float)):
        return expr.value
    if isinstance(expr, ast.Name):
        return values.get(expr.id)
    if isinstance(expr, ast.UnaryOp):
        value = _const(expr.operand, values)
        if value is None:
            return None
        if isinstance(expr.op, ast.USub):
            return -value
        if isinstance(expr.op, ast.UAdd):
            return value
    if isinstance(expr, ast.BinOp):
        left = _const(expr.left, values)
        right = _const(expr.right, values)
        if left is None or right is None:
            return None
        try:
            if isinstance(expr.op, ast.Add): return left + right
            if isinstance(expr.op, ast.Sub): return left - right
            if isinstance(expr.op, ast.Mult): return left * right
            if isinstance(expr.op, ast.Div): return left / right
            if isinstance(expr.op, ast.FloorDiv): return left // right
            if isinstance(expr.op, ast.Pow): return left ** right
        except Exception:
            return None
    return None


def _numeric_values(tree):
    values = {}
    for _ in range(4):
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign):
                value = _const(node.value, values)
                if value is not None:
                    for target in node.targets:
                        if isinstance(target, ast.Name):
                            values[target.id] = value
            elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
                value = _const(node.value, values)
                if value is not None:
                    values[node.target.id] = value
    found = set(values.values())
    for node in ast.walk(tree):
        if isinstance(node, ast.expr):
            value = _const(node, values)
            if value is not None:
                found.add(value)
    return values, found


def _descendant_count(root_pid):
    parent_of = {}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            data = (entry / 'stat').read_text()
            tail = data[data.rfind(')') + 2:].split()
            parent_of[int(entry.name)] = int(tail[1])
        except (OSError, ValueError, IndexError):
            pass
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, ppid in parent_of.items():
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return len(descendants) - 1


def _run_script(require_workers=True):
    if OUTPUT.exists():
        OUTPUT.unlink()
    err_path = '/tmp/mc_volume_stderr.txt'
    with open(err_path, 'w+') as err:
        proc = subprocess.Popen(
            ['python3', str(SCRIPT)], cwd='/home/user',
            stdout=subprocess.DEVNULL, stderr=err, start_new_session=True
        )
        maximum_children = 0
        deadline = time.time() + 240
        while proc.poll() is None:
            maximum_children = max(maximum_children, _descendant_count(proc.pid))
            if time.time() > deadline:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
                raise AssertionError('mc_volume.py did not finish within 240 seconds')
            time.sleep(0.005)
        err.seek(0)
        stderr = err.read()
    assert proc.returncode == 0, f'mc_volume.py failed with code {proc.returncode}: {stderr[-2000:]}'
    assert OUTPUT.is_file(), 'Executing mc_volume.py did not create volume_estimate.txt'
    if require_workers:
        assert maximum_children >= 4, (
            f'Execution never had 4 parallel worker processes (maximum observed: {maximum_children})'
        )


def _read_output(strict=False):
    content = OUTPUT.read_text().strip()
    match = re.search(r'Estimated Volume:\s*([0-9.]+)', content)
    assert match is not None, "Format error: Could not find 'Estimated Volume: <value>' in the output file."
    if strict:
        assert re.fullmatch(r'Estimated Volume: [0-9]+\.[0-9]{2}', content), (
            'Output must contain exactly Estimated Volume: <value> with two decimal places'
        )
    value = float(match.group(1))
    assert math.isfinite(value)
    return value


def _pdb_line(serial, element, x, y, z):
    chars = [' '] * 80
    chars[0:6] = 'ATOM  '
    chars[6:11] = f'{serial:5d}'
    chars[12:16] = f'{element + str(serial):<4}'[:4]
    chars[17:20] = 'MOL'
    chars[22:26] = f'{1:4d}'
    chars[30:38] = f'{x:8.3f}'
    chars[38:46] = f'{y:8.3f}'
    chars[46:54] = f'{z:8.3f}'
    chars[76:78] = f'{element:>2}'
    return ''.join(chars) + '\n'


def _sphere_volume(radius):
    return 4.0 * math.pi * radius ** 3 / 3.0


def _intersection_volume(r1, r2, distance):
    return (
        math.pi * (r1 + r2 - distance) ** 2
        * (distance ** 2 + 2 * distance * (r1 + r2) - 3 * (r1 - r2) ** 2)
        / (12 * distance)
    )


def test_mc_volume_script_exists():
    assert SCRIPT.is_file(), f'Script {SCRIPT} does not exist.'


def test_script_contains_required_implementation():
    source = SCRIPT.read_text()
    tree = ast.parse(source)
    values, numbers = _numeric_values(tree)

    strings = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
    joined_strings = '\n'.join(strings)
    assert '/home/user/molecule.pdb' in joined_strings, 'Script must read the specified PDB file'
    assert '/home/user/volume_estimate.txt' in joined_strings, 'Script must write the specified output file'

    slices = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Slice):
            low = _const(node.slice.lower, values)
            high = _const(node.slice.upper, values)
            slices.add((low, high))
    assert {(30, 38), (38, 46), (46, 54), (76, 78)}.issubset(slices), (
        'PDB coordinates and elements must be parsed from fixed-width columns 31-38, 39-46, 47-54, and 77-78'
    )

    constants = {n.value for n in ast.walk(tree) if isinstance(n, ast.Constant)}
    for element, radius in {'C': 1.7, 'O': 1.5, 'N': 1.55, 'H': 1.2}.items():
        assert element in constants and radius in constants, f'Missing required radius for {element}'
    assert 2_000_000 in numbers, 'The simulation must use 2,000,000 total points'
    assert 500_000 in numbers, 'Each worker must process 500,000 points'

    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module)
    assert any(name == 'numpy' or name.startswith('numpy.') for name in imported), 'NumPy must be used'
    assert any(name == 'multiprocessing' or name.startswith('multiprocessing.') for name in imported), (
        'multiprocessing must be used'
    )

    pool_with_four = False
    process_calls = 0
    range_four = False
    call_names = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = node.func.attr if isinstance(node.func, ast.Attribute) else node.func.id if isinstance(node.func, ast.Name) else ''
        call_names.append(name)
        if name == 'Pool':
            configured = _const(node.args[0], values) if node.args else None
            for keyword in node.keywords:
                if keyword.arg in ('processes', 'workers'):
                    configured = _const(keyword.value, values)
            pool_with_four |= configured == 4
        if name == 'Process':
            process_calls += 1
        if name == 'range' and node.args and _const(node.args[0], values) == 4:
            range_four = True
    assert pool_with_four or (process_calls >= 4) or (process_calls >= 1 and range_four), (
        'The script must explicitly create four multiprocessing workers'
    )
    assert any(name in ('uniform', 'random', 'random_sample', 'rand') for name in call_names), (
        'Workers must generate random points using array-based random generation'
    )
    assert any(name in ('any', 'sum', 'count_nonzero') for name in call_names), (
        'Workers must use multidimensional array operations to count points inside atom spheres'
    )


def test_volume_estimate_output():
    _run_script(require_workers=True)
    assert OUTPUT.is_file(), f'Output file {OUTPUT} does not exist.'
    vol = _read_output(strict=True)
    assert 44.0 <= vol <= 47.0, f'Value out of bounds: {vol}. Expected between 44.0 and 47.0.'


def test_script_recomputes_from_pdb_records():
    original_pdb = PDB.read_bytes()
    radii = {'C': 1.7, 'O': 1.5, 'N': 1.55, 'H': 1.2}
    # C and O overlap by an amount determined by their parsed coordinates;
    # N and H are isolated. This has an analytically known union volume.
    distance = 1.637
    shift = 8.321
    records = [
        _pdb_line(1, 'C', shift, -3.217, 2.456),
        _pdb_line(2, 'O', shift + distance, -3.217, 2.456),
        _pdb_line(3, 'N', shift + distance + 4.731, -3.217, 2.456),
        _pdb_line(4, 'H', shift + distance + 9.219, -3.217, 2.456),
    ]
    expected = sum(_sphere_volume(radii[e]) for e in ('C', 'O', 'N', 'H'))
    expected -= _intersection_volume(radii['C'], radii['O'], distance)
    try:
        PDB.write_text(''.join(records))
        _run_script(require_workers=True)
        measured = _read_output(strict=True)
        assert abs(measured - expected) <= 0.8, (
            f'Recomputed volume {measured:.2f} disagrees with the analytic union volume {expected:.2f}'
        )
    finally:
        PDB.write_bytes(original_pdb)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
