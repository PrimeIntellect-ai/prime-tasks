#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/kinetics_audit
cat <<'PY_EOF' > /tmp/kinetics_audit/sitecustomize.py
import os

_LOG = os.environ.get('KINETICS_AUDIT_LOG')

def _record(args):
    if not _LOG or args is None:
        return
    try:
        vals = tuple(float(x) for x in args)
        if len(vals) != 3:
            return
        line = '%d %.12g %.12g %.12g\n' % ((os.getpid(),) + vals)
        fd = os.open(_LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        try:
            os.write(fd, line.encode('ascii'))
        finally:
            os.close(fd)
    except Exception:
        pass

try:
    import scipy.integrate as _si

    _old_odeint = _si.odeint
    def _audited_odeint(*a, **kw):
        ode_args = kw.get('args', a[3] if len(a) > 3 else ())
        _record(ode_args)
        return _old_odeint(*a, **kw)
    _si.odeint = _audited_odeint

    _old_solve_ivp = _si.solve_ivp
    def _audited_solve_ivp(*a, **kw):
        ivp_args = kw.get('args', a[8] if len(a) > 8 else None)
        _record(ivp_args)
        return _old_solve_ivp(*a, **kw)
    _si.solve_ivp = _audited_solve_ivp
except Exception:
    pass
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path

import numpy as np
import pytest
from scipy.integrate import odeint

DATA_PATH = Path('/home/user/kinetics_data.csv')
OUTPUT_PATH = Path('/home/user/best_fit.json')
EXPECTED_KEYS = {'best_k1', 'best_k2', 'best_k3', 'sse', 'sigma_1'}
GRID = [i / 10.0 for i in range(1, 11)]


def kinetics(y, t, k1, k2, k3):
    A, B, C = y
    return [-k1 * A, k1 * A - k2 * B ** 2, k2 * B ** 2 - k3 * C]


def compute_true_sigma1(path=DATA_PATH):
    """Preserve the original independent largest-singular-value check."""
    M = []
    with open(path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            M.append([float(row['A']), float(row['B']), float(row['C'])])

    MTM = [[0.0] * 3 for _ in range(3)]
    for row in M:
        for i in range(3):
            for j in range(3):
                MTM[i][j] += row[i] * row[j]

    v = [1.0, 1.0, 1.0]
    for _ in range(100):
        v_new = [sum(MTM[i][j] * v[j] for j in range(3)) for i in range(3)]
        norm = math.sqrt(sum(x * x for x in v_new))
        v = [x / norm for x in v_new]
    v_new = [sum(MTM[i][j] * v[j] for j in range(3)) for i in range(3)]
    eigenvalue = sum(v[i] * v_new[i] for i in range(3)) / sum(v[i] * v[i] for i in range(3))
    return math.sqrt(eigenvalue)


def descendants(pid):
    parents = {}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            text = (entry / 'stat').read_text()
            rest = text[text.rfind(')') + 2:].split()
            parents[int(entry.name)] = int(rest[1])
        except Exception:
            pass
    found = set()
    changed = True
    while changed:
        changed = False
        for child, parent in parents.items():
            if child not in found and (parent == pid or parent in found):
                found.add(child)
                changed = True
    return found


def command_for(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return ['python3', str(path)]
    if suffix == '.sh':
        return ['bash', str(path)]
    if suffix == '.r' and shutil.which('Rscript'):
        return ['Rscript', str(path)]
    if suffix == '.jl' and shutil.which('julia'):
        return ['julia', str(path)]
    if os.access(path, os.X_OK):
        return [str(path)]
    return None


def candidate_scripts():
    candidates = []
    for path in Path('/home/user').glob('**/*'):
        if not path.is_file() or path in (DATA_PATH, OUTPUT_PATH):
            continue
        if len(path.relative_to('/home/user').parts) > 3:
            continue
        cmd = command_for(path)
        if cmd is None:
            continue
        try:
            mentions_output = 'best_fit.json' in path.read_text(errors='ignore')
        except Exception:
            mentions_output = False
        candidates.append((not mentions_output, -path.stat().st_mtime, path, cmd))
    candidates.sort(key=lambda x: (x[0], x[1], str(x[2])))
    return candidates


def run_command(cmd, audit_log):
    Path(audit_log).unlink(missing_ok=True)
    OUTPUT_PATH.unlink(missing_ok=True)
    env = os.environ.copy()
    env['KINETICS_AUDIT_LOG'] = audit_log
    env['PYTHONPATH'] = '/tmp/kinetics_audit' + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    proc = subprocess.Popen(cmd, cwd='/home/user', env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    maximum = 0
    chunks = []
    deadline = time.time() + 180
    while proc.poll() is None:
        maximum = max(maximum, len(descendants(proc.pid)))
        if time.time() > deadline:
            proc.kill()
            proc.wait()
            pytest.fail('Submitted script exceeded the 180 second execution limit')
        time.sleep(0.002)
    out, _ = proc.communicate()
    chunks.append(out or '')
    return proc.returncode, maximum, ''.join(chunks)


def locate_and_run(original_bytes, audit_log):
    candidates = candidate_scripts()
    assert candidates, 'No runnable analysis script was left in /home/user'
    failures = []
    for _, _, path, cmd in candidates:
        DATA_PATH.write_bytes(original_bytes)
        code, maximum, output = run_command(cmd, audit_log)
        if code == 0 and OUTPUT_PATH.is_file():
            return path, cmd, maximum
        failures.append(f'{path}: exit={code}; {output[-300:]}')
    pytest.fail('No submitted script successfully generated best_fit.json when executed. ' + ' | '.join(failures))


def load_and_check_format():
    assert OUTPUT_PATH.is_file(), f'Output file not found: {OUTPUT_PATH}'
    text = OUTPUT_PATH.read_text()
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {OUTPUT_PATH} is not valid JSON: {exc}')
    assert EXPECTED_KEYS.issubset(data.keys()), f'JSON missing expected keys. Found: {list(data.keys())}'
    for key in EXPECTED_KEYS:
        assert type(data[key]) is float, f'{key} must be a JSON float with four decimal places'
        pattern = r'"' + re.escape(key) + r'"\s*:\s*-?\d+\.\d{4}(?=\s*[,}])'
        assert re.search(pattern, text), f'{key} is not written with exactly four digits after the decimal point'
        assert math.isfinite(data[key]), f'{key} must be finite'
    return data


def read_audit(path):
    rows = []
    if Path(path).is_file():
        for line in Path(path).read_text().splitlines():
            try:
                pid, k1, k2, k3 = line.split()
                rows.append((int(pid), float(k1), float(k2), float(k3)))
            except Exception:
                pass
    return rows


def assert_complete_parallel_grid(audit_path, max_descendants):
    rows = read_audit(audit_path)
    observed = {(round(k1, 8), round(k2, 8), round(k3, 8)) for _, k1, k2, k3 in rows}
    expected = {(k1, k2, k3) for k1 in GRID for k2 in GRID for k3 in GRID}
    missing = expected - observed
    assert not missing, f'Script did not integrate all 1,000 grid combinations; {len(missing)} were not evaluated'
    worker_pids = {pid for pid, k1, k2, k3 in rows if (round(k1, 8), round(k2, 8), round(k3, 8)) in expected}
    assert len(worker_pids) >= 4, f'Grid evaluations used only {len(worker_pids)} worker process(es), not at least 4'
    assert max_descendants >= 4, 'At least four worker processes were not observed running during the search'


def write_challenge_data(path):
    t = np.linspace(0.0, 15.0, 31)
    y0 = [7.0, 1.0, 0.5]
    sol = odeint(kinetics, y0, t, args=(0.8, 0.7, 0.6))
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['t', 'A', 'B', 'C'])
        for ti, row in zip(t, sol):
            writer.writerow([ti, row[0], row[1], row[2]])


def reference_grid(path):
    raw = np.genfromtxt(path, delimiter=',', names=True)
    t = np.asarray(raw['t'], dtype=float)
    observed = np.column_stack((raw['A'], raw['B'], raw['C']))
    y0 = observed[0]
    best = None
    for k1 in GRID:
        for k2 in GRID:
            for k3 in GRID:
                sim = odeint(kinetics, y0, t, args=(k1, k2, k3))
                sse = float(np.sum((sim - observed) ** 2))
                if best is None or sse < best[0]:
                    best = (sse, k1, k2, k3, sim)
    return best


def test_final_state_and_executed_search():
    original = DATA_PATH.read_bytes()
    original_sigma = compute_true_sigma1()
    try:
        script, cmd, max_children = locate_and_run(original, '/tmp/grid_audit_original.log')
        original_result = load_and_check_format()

        # Preserve the original value assertions.
        assert abs(original_result.get('best_k1', -1) - 0.5) < 1e-4
        assert abs(original_result.get('best_k2', -1) - 0.2) < 1e-4
        assert abs(original_result.get('best_k3', -1) - 0.1) < 1e-4
        sse = original_result.get('sse', float('inf'))
        assert 0.0 <= sse < 0.001, f'Expected nonnegative SSE very close to 0, got {sse}'
        assert abs(original_result.get('sigma_1', -1) - original_sigma) < 0.005
        assert_complete_parallel_grid('/tmp/grid_audit_original.log', max_children)

        # Re-execute the same artifact on verifier-generated data so fixed answers cannot pass.
        write_challenge_data(DATA_PATH)
        code, hidden_max_children, output = run_command(cmd, '/tmp/grid_audit_hidden.log')
        assert code == 0 and OUTPUT_PATH.is_file(), f'Script failed on verifier-generated data: {output[-500:]}'
        hidden_result = load_and_check_format()
        best_sse, k1, k2, k3, simulation = reference_grid(DATA_PATH)
        sigma = float(np.linalg.svd(simulation, compute_uv=False)[0])
        assert abs(hidden_result['best_k1'] - round(k1, 4)) < 5e-5
        assert abs(hidden_result['best_k2'] - round(k2, 4)) < 5e-5
        assert abs(hidden_result['best_k3'] - round(k3, 4)) < 5e-5
        assert hidden_result['sse'] >= 0.0
        assert abs(hidden_result['sse'] - round(best_sse, 4)) < 5e-5
        assert abs(hidden_result['sigma_1'] - round(sigma, 4)) < 5e-5
        assert_complete_parallel_grid('/tmp/grid_audit_hidden.log', hidden_max_children)
    finally:
        DATA_PATH.write_bytes(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
