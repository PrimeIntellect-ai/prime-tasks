#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
from pathlib import Path

import numpy as np
from scipy.stats import wasserstein_distance

HOME = Path('/home/user')
SCRIPT = HOME / 'regression_test.py'
LEGACY = HOME / 'legacy_sim.py'
FAST = HOME / 'fast_sim.py'
LEGACY_OUT = HOME / 'legacy_out.npy'
FAST_OUT = HOME / 'fast_out.npy'
RESULT = HOME / 'max_wasserstein.txt'
HOOK_DIR = Path('/tmp/wasserstein_hook')
HOOK_LOG = Path('/tmp/wasserstein_calls.log')


def install_hook():
    HOOK_DIR.mkdir(exist_ok=True)
    (HOOK_DIR / 'sitecustomize.py').write_text(
        "import os\n"
        "import scipy.stats\n"
        "_original = scipy.stats.wasserstein_distance\n"
        "def _recording_wasserstein(*args, **kwargs):\n"
        "    path = os.environ.get('WASSERSTEIN_CALL_LOG')\n"
        "    if path:\n"
        "        with open(path, 'a') as f:\n"
        "            f.write('call\\n')\n"
        "    return _original(*args, **kwargs)\n"
        "scipy.stats.wasserstein_distance = _recording_wasserstein\n"
    )


def execute_submission():
    for path in (LEGACY_OUT, FAST_OUT, RESULT, HOOK_LOG):
        path.unlink(missing_ok=True)
    env = os.environ.copy()
    env['PYTHONPATH'] = str(HOOK_DIR)
    env['WASSERSTEIN_CALL_LOG'] = str(HOOK_LOG)
    return subprocess.run(
        ['python3', str(SCRIPT)], cwd=str(HOME), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )


def validate_outputs(expected_code, expected_legacy, expected_fast):
    proc = execute_submission()
    assert proc.returncode == expected_code, (
        f'Expected exit code {expected_code}, got {proc.returncode}. '
        f'stdout={proc.stdout!r}, stderr={proc.stderr!r}'
    )
    assert LEGACY_OUT.is_file(), 'legacy_out.npy was not generated'
    assert FAST_OUT.is_file(), 'fast_out.npy was not generated'
    legacy = np.load(LEGACY_OUT)
    fast = np.load(FAST_OUT)
    assert legacy.shape == (1000, 50)
    assert fast.shape == (1000, 50)
    np.testing.assert_allclose(legacy, expected_legacy, rtol=0, atol=0)
    np.testing.assert_allclose(fast, expected_fast, rtol=0, atol=0)

    distances = [wasserstein_distance(legacy[:, i], fast[:, i]) for i in range(50)]
    expected_text = f'{max(distances):.6f}'
    assert RESULT.is_file(), f'Missing file: {RESULT}'
    content = RESULT.read_text().strip()
    assert re.fullmatch(r'\d+\.\d{6}', content), 'Result is not formatted to exactly 6 decimal places'
    assert content == expected_text, f'Expected {expected_text!r}, got {content!r}'

    calls = HOOK_LOG.read_text().splitlines() if HOOK_LOG.exists() else []
    assert len(calls) >= 50, 'scipy.stats.wasserstein_distance was not called for all 50 features'
    return content


def test_regression_script_end_to_end():
    # Preserve the original assertion that the requested artifact exists.
    assert SCRIPT.is_file(), f'Missing file: {SCRIPT}'
    install_hook()

    rng = np.random.RandomState(12345)
    expected_legacy = rng.normal(loc=np.arange(50), scale=1.0, size=(1000, 50))
    expected_fast = expected_legacy.copy()
    expected_fast[:, 24] += 0.0035

    original_fast = FAST.read_bytes()
    try:
        # Execute against the shipped simulations and verify the seed, arrays,
        # metric, formatting, SciPy calls, and successful exit status.
        content = validate_outputs(0, expected_legacy, expected_fast)
        # Preserve the original exact-content assertion.
        assert content == '0.003500', f"Expected '0.003500' in {RESULT}, but got {content!r}"

        # Exercise the required failure branch with an unpredictable discrepancy.
        delta = secrets.SystemRandom().randint(15001, 49000) / 1_000_000
        column = secrets.SystemRandom().randrange(50)
        FAST.write_text(
            "import sys\n"
            "import numpy as np\n"
            "seed = int(sys.argv[1])\n"
            "np.random.seed(seed)\n"
            "data = np.random.normal(loc=np.arange(50), scale=1.0, size=(1000, 50))\n"
            f"data[:, {column}] += {delta!r}\n"
            "np.save('fast_out.npy', data)\n"
        )
        changed_fast = expected_legacy.copy()
        changed_fast[:, column] += delta
        validate_outputs(1, expected_legacy, changed_fast)
    finally:
        FAST.write_bytes(original_fast)

    # Leave the required final artifact generated from the original simulations.
    final_content = validate_outputs(0, expected_legacy, expected_fast)
    assert final_content == '0.003500', f"Expected '0.003500' in {RESULT}, but got {final_content!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
