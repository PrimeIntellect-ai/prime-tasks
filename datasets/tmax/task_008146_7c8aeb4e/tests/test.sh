#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys

import numpy as np
import pandas as pd
from scipy.stats import gaussian_kde

RESULT = Path('/home/user/integral_result.txt')
CSV = Path('/home/user/sim_data.csv')


def test_integral_result_exists_and_format():
    """Preserve the original result and accuracy assertions."""
    path = "/home/user/integral_result.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a regular file."

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content, f"File {path} is empty."
    assert "." in content, "Result must contain a decimal point."
    parts = content.split(".")
    assert len(parts) == 2, "Result must contain exactly one decimal point."
    assert len(parts[1]) == 12, (
        f"Result must be formatted to exactly 12 decimal places, found {len(parts[1])}."
    )

    try:
        val = float(content)
    except ValueError:
        assert False, f"Result '{content}' is not a valid float."

    expected = 0.999917520038
    assert math.isclose(val, expected, abs_tol=1e-7), \
        f"Calculated integral {val} is not correct. Expected roughly {expected}."


def find_submission_script():
    candidates = []
    for path in Path('/home/user').rglob('*.py'):
        if path == Path('/home/user/setup.py') or not path.is_file():
            continue
        try:
            source = path.read_text(encoding='utf-8')
            compile(source, str(path), 'exec')
        except (OSError, UnicodeDecodeError, SyntaxError):
            continue
        score = sum(token in source for token in (
            'sim_data.csv', 'integral_result.txt', 'gaussian_kde', 'fsum'
        ))
        candidates.append((score, path.stat().st_mtime_ns, path))

    assert candidates, "No executable Python submission script was found under /home/user."
    candidates.sort(reverse=True)
    script = candidates[0][2]
    source = script.read_text(encoding='utf-8')
    assert 'gaussian_kde' in source, "The submission script does not use scipy.stats.gaussian_kde."
    assert 'fsum' in source, "The submission script does not use math.fsum()."
    return script


def test_script_executes_pipeline_on_fresh_data(tmp_path):
    script = find_submission_script()
    original_csv = CSV.read_bytes()
    original_result = RESULT.read_bytes()

    seed = secrets.randbits(32)
    rng = np.random.default_rng(seed)
    values = rng.normal(loc=rng.uniform(-0.4, 0.4), scale=rng.uniform(0.55, 1.1), size=(7, 5))
    values[1, 2] = np.nan
    values[5, 0] = np.nan
    frame = pd.DataFrame(values, columns=['v1', 'v2', 'v3', 'v4', 'v5'])
    frame.insert(0, 'timestamp', pd.date_range('2026-01-01', periods=len(frame), freq='h').astype(str))

    trace = tmp_path / 'trace.jsonl'
    hook_dir = tmp_path / 'hook'
    hook_dir.mkdir()
    offset = 0.01 + secrets.randbelow(8_000_000) / 1_000_000_000.0

    try:
        frame.to_csv(CSV, index=False)
        reread = pd.read_csv(CSV)
        expected_data = reread.drop(columns=['timestamp']).to_numpy(dtype=float).ravel()
        expected_data = expected_data[~np.isnan(expected_data)]

        points = np.linspace(-5.0, 5.0, 1_000_000, endpoint=True)
        density = gaussian_kde(expected_data)(points)
        areas = (density[:-1] + density[1:]) * (points[1:] - points[:-1]) * 0.5
        expected_base = math.fsum(areas)
        expected_written = f"{expected_base + offset:.12f}"

        hook = f'''\
import json
import math
from pathlib import Path
import numpy as np
import scipy.stats

_TRACE = Path({str(trace)!r})
_EXPECTED = np.asarray({expected_data.tolist()!r}, dtype=float)
_OFFSET = {offset!r}
_orig_fsum = math.fsum
_orig_kde = scipy.stats.gaussian_kde


def _log(event):
    with _TRACE.open('a', encoding='utf-8') as f:
        f.write(json.dumps(event) + "\\n")


def checked_kde(dataset, *args, **kwargs):
    supplied = np.asarray(dataset, dtype=float).reshape(-1)
    if supplied.shape != _EXPECTED.shape or not np.allclose(supplied, _EXPECTED, rtol=0, atol=1e-12):
        raise AssertionError('KDE was not fitted to all non-NaN numerical CSV values in flattened order')
    _log({{'kind': 'fit', 'count': int(supplied.size)}})
    inner = _orig_kde(dataset, *args, **kwargs)

    class KDEProxy:
        def _evaluate(self, xs):
            arr = np.asarray(xs, dtype=float).reshape(-1)
            if arr.size != 1_000_000:
                raise AssertionError('KDE must be evaluated at exactly 1,000,000 points')
            reference = np.linspace(-5.0, 5.0, 1_000_000, endpoint=True)
            if not np.allclose(arr, reference, rtol=0, atol=2e-15):
                raise AssertionError('KDE evaluation points are not evenly spaced over [-5, 5]')
            _log({{'kind': 'evaluate', 'count': int(arr.size)}})
            return inner(xs)

        def __call__(self, xs):
            return self._evaluate(xs)

        def evaluate(self, xs):
            return self._evaluate(xs)

        def pdf(self, xs):
            return self._evaluate(xs)

        def __getattr__(self, name):
            return getattr(inner, name)

    return KDEProxy()


def checked_fsum(iterable):
    try:
        count = len(iterable)
        values = iterable
    except TypeError:
        values = list(iterable)
        count = len(values)
    base = _orig_fsum(values)
    _log({{'kind': 'fsum', 'count': int(count), 'base': float(base)}})
    if count == 999999:
        return base + _OFFSET
    return base


scipy.stats.gaussian_kde = checked_kde
math.fsum = checked_fsum
'''
        (hook_dir / 'sitecustomize.py').write_text(hook, encoding='utf-8')

        env = os.environ.copy()
        old_pythonpath = env.get('PYTHONPATH', '')
        env['PYTHONPATH'] = str(hook_dir) + (os.pathsep + old_pythonpath if old_pythonpath else '')
        completed = subprocess.run(
            [sys.executable, str(script)],
            cwd='/home/user',
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=240,
        )
        assert completed.returncode == 0, (
            f"Submission script failed on fresh observational data.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        assert RESULT.is_file(), "Executing the submission script did not create integral_result.txt."
        raw = RESULT.read_text(encoding='utf-8')
        assert re.fullmatch(r'-?\d+\.\d{12}\n?', raw), "Fresh result is not formatted to exactly 12 decimal places."
        assert raw.strip() == expected_written, (
            f"Fresh-data result was {raw.strip()!r}; expected {expected_written!r}. "
            "The final trapezoid reduction must use math.fsum()."
        )

        assert trace.exists(), "The executed script did not call the instrumented KDE and math.fsum APIs."
        events = [json.loads(line) for line in trace.read_text().splitlines() if line.strip()]
        assert any(e.get('kind') == 'fit' for e in events), "No Gaussian KDE fit was observed."
        assert any(e.get('kind') == 'evaluate' and e.get('count') == 1_000_000 for e in events), \
            "The fitted KDE was not evaluated on exactly 1,000,000 required points."
        area_sums = [e for e in events if e.get('kind') == 'fsum' and e.get('count') == 999999]
        assert area_sums, "math.fsum() was not called on the 999,999 individual trapezoid areas."
        assert any(math.isclose(e['base'], expected_base, rel_tol=0, abs_tol=2e-12) for e in area_sums), \
            "math.fsum() did not receive the correctly computed individual trapezoid areas."
    finally:
        CSV.write_bytes(original_csv)
        RESULT.write_bytes(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
