#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import stat
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pytest

EXE = Path('/home/user/bin/score_calc')
RESULT = Path('/home/user/result.json')
DATASET = Path('/home/user/data/sequences.txt')


def model(lines, x):
    scores = []
    for line in lines:
        seq = line.strip()
        gc = sum(c in 'GC' for c in seq)
        at = sum(c in 'AT' for c in seq)
        scores.append(gc * x * x + at * x)
    return sum(scores) / len(scores)


def run_executable(lines, x):
    with tempfile.NamedTemporaryFile('w', delete=False) as f:
        f.write('\n'.join(lines) + '\n')
        name = f.name
    try:
        proc = subprocess.run(
            [str(EXE), name, repr(float(x))],
            text=True, capture_output=True, timeout=10
        )
        assert proc.returncode == 0, proc.stderr
        return float(proc.stdout.strip())
    finally:
        os.unlink(name)


def test_executable_exists_and_compiled():
    exe_path = str(EXE)
    assert os.path.exists(exe_path), f'Executable not found at {exe_path}'
    assert os.path.isfile(exe_path), f'{exe_path} is not a file'

    st = os.stat(exe_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'{exe_path} is not executable'
    with open(exe_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{exe_path} is not a compiled ELF executable'

    # Exercise the submitted executable on verifier-generated inputs and x values.
    cases = [
        (['GCAAT', 'GGGAAA', 'TTCCG'], 0.375),
        (['G' * 7 + 'A' * 3, 'C' * 2 + 'T' * 11, 'ACGTACGT'], 2.7182818),
        (['A', 'GC', 'GGGGTT', 'CCCCAAAAA'], 5.125),
    ]
    for lines, x in cases:
        observed = run_executable(lines, x)
        expected = model(lines, x)
        assert math.isclose(observed, expected, rel_tol=0, abs_tol=1e-5), \
            f'score_calc returned {observed}, expected {expected}'


def test_result_json_exists():
    json_path = str(RESULT)
    assert os.path.exists(json_path), f'Result file not found at {json_path}'
    assert os.path.isfile(json_path), f'{json_path} is not a file'


def load_result(path=RESULT):
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'{path} does not contain valid JSON')


def assert_result_shape(data):
    expected_keys = {'optimal_x', 'ci_lower', 'ci_upper'}
    assert set(data.keys()) == expected_keys, \
        f'JSON keys must be exactly {expected_keys}, found {set(data.keys())}'
    for key in expected_keys:
        assert isinstance(data[key], (int, float)), f'{key} must be a number'
        assert math.isfinite(data[key]), f'{key} must be finite'


def test_result_json_content():
    data = load_result()
    assert_result_shape(data)

    assert math.isclose(data['optimal_x'], 4.0000, abs_tol=1e-4), \
        f"Expected optimal_x to be 4.0000, got {data['optimal_x']}"
    assert math.isclose(data['ci_lower'], 3.9161, abs_tol=1e-4), \
        f"Expected ci_lower to be 3.9161, got {data['ci_lower']}"
    assert math.isclose(data['ci_upper'], 4.0931, abs_tol=1e-4), \
        f"Expected ci_upper to be 4.0931, got {data['ci_upper']}"


def positive_root(lines):
    gc = np.mean([sum(c in 'GC' for c in s) for s in lines])
    at = np.mean([sum(c in 'AT' for c in s) for s in lines])
    if gc == 0:
        return 500.0 / at
    return (-at + math.sqrt(at * at + 2000.0 * gc)) / (2.0 * gc)


def expected_for(lines):
    optimum = positive_root(lines)
    np.random.seed(42)
    roots = []
    arr = np.asarray(lines)
    for _ in range(1000):
        sample = np.random.choice(arr, size=100, replace=True).tolist()
        roots.append(positive_root(sample))
    lo, hi = np.percentile(roots, [2.5, 97.5])
    return {
        'optimal_x': round(float(optimum), 4),
        'ci_lower': round(float(lo), 4),
        'ci_upper': round(float(hi), 4),
    }


def find_python_scripts():
    candidates = []
    excluded = {'.cache', '__pycache__', '.local'}
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in excluded]
        for filename in files:
            if not filename.endswith('.py'):
                continue
            path = Path(root) / filename
            try:
                text = path.read_text(errors='ignore')
            except OSError:
                continue
            score = sum(token in text for token in (
                'score_calc', 'sequences.txt', 'numpy', 'np.', 'bootstrap',
                'result.json', 'optimize', 'fsolve', 'minimize'
            ))
            if 'score_calc' in text and 'result.json' in text:
                candidates.append((score, path))
    return [p for _, p in sorted(candidates, key=lambda item: (-item[0], str(item[1])))]


def test_script_recomputes_with_binary_and_exact_bootstrap_count():
    scripts = find_python_scripts()
    assert scripts, 'No Python optimization/bootstrap script was found under /home/user'

    # A verifier-controlled, non-symmetric dataset prevents hardcoded answers from
    # passing. Its sequences vary enough that all 1000 seeded resamples have unique
    # file contents in practice.
    varied = []
    for i in range(100):
        gc = 4 + (i * 11) % 37
        at = 8 + (i * 17) % 43
        seq = ('G' * gc) + ('A' * at)
        shift = i % len(seq)
        varied.append(seq[shift:] + seq[:shift])
    expected = expected_for(varied)

    original_dataset = DATASET.read_bytes()
    original_result = RESULT.read_bytes() if RESULT.exists() else None
    backing = EXE.with_name('.score_calc.verifier_backing')
    log_path = Path('/tmp/score_calc_calls.jsonl')
    success = False
    failures = []

    os.replace(EXE, backing)
    wrapper = f'''#!/usr/bin/env python3
import hashlib, json, os, sys
BACKING = {str(backing)!r}
LOG = {str(log_path)!r}
path = sys.argv[1] if len(sys.argv) > 1 else ''
x_text = sys.argv[2] if len(sys.argv) > 2 else ''
record = {{'path': path, 'x': x_text}}
try:
    raw = open(path, 'rb').read()
    lines = [s.strip() for s in raw.decode().splitlines() if s.strip()]
    x = float(x_text)
    gc = sum(sum(c in 'GC' for c in s) for s in lines)
    at = sum(sum(c in 'AT' for c in s) for s in lines)
    record.update({{'hash': hashlib.sha256(raw).hexdigest(), 'n': len(lines),
                   'score': (gc*x*x + at*x) / len(lines)}})
except Exception as e:
    record['error'] = repr(e)
with open(LOG, 'a') as out:
    out.write(json.dumps(record) + '\\n')
os.execv(BACKING, [BACKING] + sys.argv[1:])
'''
    EXE.write_text(wrapper)
    EXE.chmod(0o755)

    try:
        for script in scripts:
            DATASET.write_text('\n'.join(varied) + '\n')
            if RESULT.exists():
                RESULT.unlink()
            log_path.write_text('')
            try:
                proc = subprocess.run(
                    ['python3', str(script)], cwd=str(script.parent),
                    text=True, capture_output=True, timeout=300,
                    env={**os.environ, 'HOME': '/home/user'}
                )
                assert proc.returncode == 0, proc.stderr[-2000:]
                assert RESULT.is_file(), 'script did not create /home/user/result.json'
                data = load_result()
                assert_result_shape(data)
                for key, value in expected.items():
                    assert math.isclose(data[key], value, rel_tol=0, abs_tol=1e-4), \
                        f'{key}: expected {value}, got {data[key]}'

                records = [json.loads(line) for line in log_path.read_text().splitlines() if line]
                by_hash = {}
                for rec in records:
                    if rec.get('n') == 100 and 'hash' in rec and 'score' in rec:
                        by_hash.setdefault(rec['hash'], []).append(rec['score'])

                # One full-dataset optimization plus exactly 1000 bootstrap
                # resamples must have been sent through the compiled binary.
                assert len(by_hash) == 1001, \
                    f'expected 1001 distinct datasets evaluated by score_calc, found {len(by_hash)}'
                for digest, scores in by_hash.items():
                    assert any(abs(score - 500.0) <= 0.05 for score in scores), \
                        f'dataset {digest[:12]} was not numerically solved to score 500'
                success = True
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert success, 'No submitted Python script passed execution checks: ' + ' | '.join(failures)
    finally:
        if EXE.exists():
            EXE.unlink()
        os.replace(backing, EXE)
        DATASET.write_bytes(original_dataset)
        if original_result is None:
            if RESULT.exists():
                RESULT.unlink()
        else:
            RESULT.write_bytes(original_result)
        if log_path.exists():
            log_path.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
