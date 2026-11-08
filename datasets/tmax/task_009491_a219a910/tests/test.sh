#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy.stats import ks_2samp, wasserstein_distance

HOME = Path('/home/user')
GEN = HOME / 'mc_generator.py'
EVAL = HOME / 'evaluator.py'
CONV = HOME / 'test_convergence.sh'
REF = HOME / 'reference_100000.csv'


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def load_csv(path, expected_n=None):
    path = Path(path)
    assert path.exists(), f'{path} was not created'
    with path.open() as f:
        assert f.readline().strip() == 'x,y,z', f'Incorrect CSV header in {path}'
    data = np.genfromtxt(path, delimiter=',', skip_header=1)
    if data.ndim == 1:
        data = data.reshape(1, -1)
    assert data.ndim == 2 and data.shape[1] == 3, f'Invalid CSV shape: {data.shape}'
    if expected_n is not None:
        assert len(data) == expected_n, f'Expected {expected_n} rows, got {len(data)}'
    assert np.isfinite(data).all(), 'Generated data contains non-finite values'
    return data


def assert_target_distribution(data, reference):
    n = len(data)
    assert np.all((data >= -1.0) & (data <= 1.0)), 'Samples are outside [-1, 1]^3'
    assert len(np.unique(data, axis=0)) >= int(0.98 * n), 'Too many repeated/fabricated points'

    radii = np.linalg.norm(data, axis=1)
    ref_radii = np.linalg.norm(reference, axis=1)
    assert ks_2samp(radii, ref_radii).statistic < 0.04, 'Radial distribution is incorrect'
    for column in range(3):
        assert ks_2samp(data[:, column], reference[:, column]).statistic < 0.04, \
            f'Coordinate {column} distribution is incorrect'

    # For p(x,y,z) proportional to x^2+y^2+z^2 on the cube, E[r^2] = 19/15.
    mean_r2 = np.mean(np.sum(data * data, axis=1))
    assert abs(mean_r2 - 19.0 / 15.0) < 0.08, f'Mean r^2 is {mean_r2}, expected about {19/15}'


def test_scripts_exist_and_executable():
    for script in (GEN, EVAL, CONV):
        assert script.exists(), f'Script {script} does not exist'
        assert os.access(script, os.X_OK), f'Script {script} is not executable'


def test_mc_generator_distribution_and_interface(tmp_path):
    reference = load_csv(REF, 100000)

    # Preserve the original fixed N=10000, seed=42 execution and structural checks.
    fixed = tmp_path / 'fixed.csv'
    result = run([sys.executable, str(GEN), '10000', '42', str(fixed)])
    assert result.returncode == 0, f'mc_generator.py failed: {result.stderr}'
    fixed_data = load_csv(fixed, 10000)
    assert_target_distribution(fixed_data, reference)

    # Exercise an unpredictable seed and size, reproducibility, and seed use.
    seed = secrets.randbelow(2**31 - 2) + 1
    n = 7000 + secrets.randbelow(1001)
    out1, out2, out3 = tmp_path/'a.csv', tmp_path/'b.csv', tmp_path/'c.csv'
    for s, out in ((seed, out1), (seed, out2), (seed + 1, out3)):
        result = run([sys.executable, str(GEN), str(n), str(s), str(out)])
        assert result.returncode == 0, f'mc_generator.py failed: {result.stderr}'
    a, b, c = load_csv(out1, n), load_csv(out2, n), load_csv(out3, n)
    assert np.array_equal(a, b), 'Same seed does not reproduce the same samples'
    assert not np.array_equal(a, c), 'Different seeds produce identical samples'
    assert_target_distribution(a, reference)
    assert_target_distribution(c, reference)

    assert run([sys.executable, str(GEN)]).returncode != 0, 'Generator accepts missing arguments'
    assert run([sys.executable, str(GEN), '10', '1', str(tmp_path/'x.csv'), 'extra']).returncode != 0, \
        'Generator accepts more than three arguments'


def write_csv(path, array):
    np.savetxt(path, array, delimiter=',', header='x,y,z', comments='')


def test_evaluator_computation(tmp_path):
    rng = np.random.default_rng(secrets.randbits(63))
    cases = [
        (rng.normal(size=(137, 3)), rng.uniform(-2, 2, size=(211, 3))),
        (rng.uniform(-1, 1, size=(53, 3)), rng.uniform(-1, 1, size=(53, 3))),
    ]
    for index, (a, b) in enumerate(cases):
        p1, p2 = tmp_path/f'eval_a_{index}.csv', tmp_path/f'eval_b_{index}.csv'
        write_csv(p1, a)
        write_csv(p2, b)
        result = run([sys.executable, str(EVAL), str(p1), str(p2)])
        assert result.returncode == 0, f'evaluator.py failed: {result.stderr}'
        tokens = result.stdout.strip().split()
        assert len(tokens) == 1, f'Evaluator must print only one float, got {result.stdout!r}'
        actual = float(tokens[0])
        expected = wasserstein_distance(np.linalg.norm(a, axis=1), np.linalg.norm(b, axis=1))
        assert np.isfinite(actual) and abs(actual - expected) <= 1e-10 * max(1.0, abs(expected)), \
            f'Incorrect Wasserstein distance: got {actual}, expected {expected}'


def make_wrapper(path, backup, log):
    path.write_text(
        '#!/usr/bin/env python3\n'
        'import json, os, sys\n'
        f'with open({str(log)!r}, "a") as f:\n'
        '    f.write(json.dumps(sys.argv[1:]) + "\\n")\n'
        f'os.execv(sys.executable, [sys.executable, {str(backup)!r}] + sys.argv[1:])\n'
    )
    path.chmod(0o755)


def read_log(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def test_convergence_script_execution(tmp_path):
    # Wrap both programs so the convergence script must actually invoke the submitted artifacts.
    token = secrets.token_hex(12)
    gen_backup = tmp_path / f'generator_{token}.py'
    eval_backup = tmp_path / f'evaluator_{token}.py'
    gen_log, eval_log = tmp_path/'gen_calls.log', tmp_path/'eval_calls.log'
    GEN.rename(gen_backup)
    EVAL.rename(eval_backup)
    try:
        make_wrapper(GEN, gen_backup, gen_log)
        make_wrapper(EVAL, eval_backup, eval_log)
        for name in ('results.json', 'gen_100.csv', 'gen_1000.csv', 'gen_10000.csv'):
            p = HOME / name
            if p.exists():
                p.unlink()
        result = run(['bash', str(CONV)], cwd=str(HOME))
    finally:
        if GEN.exists():
            GEN.unlink()
        if EVAL.exists():
            EVAL.unlink()
        gen_backup.rename(GEN)
        eval_backup.rename(EVAL)
        GEN.chmod(0o755)
        EVAL.chmod(0o755)

    assert result.returncode == 0, f'test_convergence.sh failed with error: {result.stderr}'
    results_file = HOME / 'results.json'
    assert results_file.exists(), 'results.json was not created'
    try:
        data = json.loads(results_file.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError('results.json is not valid JSON') from exc
    assert set(data) == {'100', '1000', '10000'}, 'results.json must contain exactly the required keys'

    reference = load_csv(REF, 100000)
    ref_r = np.linalg.norm(reference, axis=1)
    expected = {}
    for n in (100, 1000, 10000):
        generated = load_csv(HOME / f'gen_{n}.csv', n)
        assert np.all((generated >= -1) & (generated <= 1)), 'Convergence output is outside the cube'
        expected[str(n)] = wasserstein_distance(np.linalg.norm(generated, axis=1), ref_r)
        reported = float(data[str(n)])
        assert np.isfinite(reported), 'results.json contains a non-finite distance'
        assert abs(reported - expected[str(n)]) <= 1e-9 * max(1.0, expected[str(n)]), \
            f'Reported distance for {n} was fabricated or computed incorrectly'

    v100, v1000, v10000 = float(data['100']), float(data['1000']), float(data['10000'])
    assert v10000 < v100, f'Convergence not observed: dist(10000)={v10000} >= dist(100)={v100}'

    generator_calls = read_log(gen_log)
    evaluator_calls = read_log(eval_log)
    for n in (100, 1000, 10000):
        assert any(len(args) == 3 and args[0] == str(n) and args[1] == '42' and
                   Path(args[2]).name == f'gen_{n}.csv' for args in generator_calls), \
            f'test_convergence.sh did not invoke mc_generator.py correctly for N={n}'
        assert any(len(args) == 2 and {Path(args[0]).name, Path(args[1]).name} ==
                   {f'gen_{n}.csv', 'reference_100000.csv'} for args in evaluator_calls), \
            f'test_convergence.sh did not invoke evaluator.py correctly for N={n}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
