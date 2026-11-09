#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import subprocess
from pathlib import Path

import numpy as np
import pytest
from packaging.requirements import Requirement
from packaging.version import Version

PROJECT = Path('/home/user/signal_port')
ORACLE = Path('/app/legacy_oracle')


def test_requirements_conflict_fixed():
    requirements_path = PROJECT / 'requirements.txt'
    assert requirements_path.is_file(), 'requirements.txt is missing'

    requirements = []
    for raw_line in requirements_path.read_text().splitlines():
        line = raw_line.split('#', 1)[0].strip()
        if line:
            requirements.append(Requirement(line))

    by_name = {}
    for requirement in requirements:
        if requirement.marker is None or requirement.marker.evaluate():
            by_name.setdefault(requirement.name.lower(), []).append(requirement)

    for dependency in ('numpy', 'pandas', 'pytest', 'requests', 'urllib3'):
        assert dependency in by_name, f'{dependency} was removed from requirements.txt'

    # The reported conflict must be resolved rather than hidden by removing a dependency.
    compatible_urllib3_versions = [
        Version('1.26.0'), Version('1.26.20'), Version('2.0.0'), Version('2.5.0')
    ]
    assert any(
        all(version in requirement.specifier for requirement in by_name['urllib3'])
        for version in compatible_urllib3_versions
    ), 'urllib3 constraints still exclude all versions compatible with the required requests release'

    completed = subprocess.run(
        [sys.executable, '-m', 'pytest', str(PROJECT / 'tests'), '-q'],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert completed.returncode == 0, f'Project pytest suite does not run successfully:\n{completed.stdout}'


def test_processor_accuracy():
    sys.path.insert(0, str(PROJECT))
    try:
        from processor import process_signal
    except ImportError as exc:
        pytest.fail(f'Failed to import process_signal from {PROJECT / "processor.py"}: {exc}')

    np.random.seed(42)
    test_inputs = np.random.randint(
        -2000000000, 2000000000, size=50000, dtype=np.int32
    ).tolist()

    try:
        agent_outputs = process_signal(test_inputs)
    except Exception as exc:
        pytest.fail(f'process_signal raised an exception during execution: {exc}')

    proc = subprocess.run(
        [str(ORACLE)],
        input=' '.join(map(str, test_inputs)),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        check=True,
    )
    oracle_outputs = [int(value) for value in proc.stdout.split()]

    assert len(agent_outputs) == len(oracle_outputs), (
        f'Output lengths differ: agent returned {len(agent_outputs)} items, '
        f'but oracle returned {len(oracle_outputs)}'
    )
    assert list(agent_outputs) == oracle_outputs, 'processor.py did not achieve a perfect 100% match'


def test_regression_script_exists_and_detects_mismatch():
    regression = PROJECT / 'regression.py'
    assert regression.is_file(), 'regression.py was not created'

    normal = subprocess.run(
        [sys.executable, str(regression)],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert normal.returncode == 0, f'regression.py failed against the real oracle:\n{normal.stdout}'

    backup = Path('/app/.legacy_oracle.verifier.real')
    input_log = Path('/tmp/regression_oracle_input.txt')
    wrapper_source = '''#!/usr/bin/env python3
import pathlib
import subprocess
import sys

data = sys.stdin.read()
pathlib.Path('/tmp/regression_oracle_input.txt').write_text(data)
result = subprocess.run(
    ['/app/.legacy_oracle.verifier.real'], input=data, text=True,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE
)
values = result.stdout.split()
if values:
    values[0] = str(int(values[0]) + 1)
sys.stdout.write((' '.join(values) + ' ') if values else '')
sys.stderr.write(result.stderr)
sys.exit(result.returncode)
'''

    if backup.exists():
        backup.unlink()
    input_log.unlink(missing_ok=True)
    ORACLE.rename(backup)
    try:
        ORACLE.write_text(wrapper_source)
        ORACLE.chmod(0o755)
        corrupted = subprocess.run(
            [sys.executable, str(regression)],
            cwd=PROJECT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
        )
    finally:
        ORACLE.unlink(missing_ok=True)
        backup.rename(ORACLE)
        ORACLE.chmod(0o755)

    assert input_log.is_file(), 'regression.py did not invoke /app/legacy_oracle via subprocess'
    generated_inputs = input_log.read_text().split()
    assert len(generated_inputs) == 10000, (
        f'regression.py sent {len(generated_inputs)} values to the oracle instead of 10,000'
    )
    assert len(set(generated_inputs)) > 100, 'regression.py did not generate a meaningful random input set'
    assert corrupted.returncode != 0, (
        'regression.py succeeded after the oracle output was deliberately corrupted; '
        'it does not assert complete equality with processor.py'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
