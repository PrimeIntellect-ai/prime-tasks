#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import random
import shutil
import signal
import subprocess
import sys
import tempfile

import pytest

PROCESSOR_PATH = '/home/user/log_processor.py'
MRE_PATH = '/home/user/mre_log.txt'
PRODUCTION_PATH = '/home/user/production_logs.txt'
REGRESSION_PATH = '/home/user/regression_test.py'
EXPECTED_ERROR = 'Cycle detected in job dependencies'


def load_processor():
    assert os.path.isfile(PROCESSOR_PATH), f'File {PROCESSOR_PATH} does not exist.'
    spec = importlib.util.spec_from_file_location('submitted_log_processor', PROCESSOR_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, 'process_logs'), 'log_processor.py must have process_logs function.'
    assert callable(module.process_logs), 'process_logs must be callable.'
    assert hasattr(module, 'resolve_dependencies'), 'log_processor.py must have resolve_dependencies function.'
    assert callable(module.resolve_dependencies), 'resolve_dependencies must be callable.'
    return module


class CallTimedOut(Exception):
    pass


def call_with_timeout(fn, *args, seconds=2):
    def handler(signum, frame):
        raise CallTimedOut('call timed out')

    old_handler = signal.signal(signal.SIGALRM, handler)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        return fn(*args)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old_handler)


def parsed_trigger_has_reachable_cycle(lines):
    dependencies = {}
    pending = set()
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        parts = line.split(',')
        if len(parts) not in (2, 3):
            return False
        job, action = parts[0], parts[1]
        if action == 'REQUIRES':
            if len(parts) != 3 or not job or not parts[2]:
                return False
            dep = parts[2]
            dependencies.setdefault(job, []).append(dep)
            pending.add(job)
            pending.add(dep)
        elif action == 'COMPLETED':
            if len(parts) != 2:
                return False
            if job not in pending:
                continue
            visiting = set()
            visited = set()

            def cyclic(node):
                if node in visiting:
                    return True
                if node in visited:
                    return False
                visiting.add(node)
                for dep in dependencies.get(node, []):
                    if cyclic(dep):
                        return True
                visiting.remove(node)
                visited.add(node)
                return False

            if cyclic(job):
                return True
            pending.remove(job)
        else:
            return False
    return False


def assert_expected_cycle_error(module, lines):
    try:
        call_with_timeout(module.process_logs, list(lines), seconds=2)
    except ValueError as exc:
        assert str(exc) == EXPECTED_ERROR, f'Incorrect ValueError message: {exc}'
    except CallTimedOut:
        pytest.fail('process_logs hung on cyclic dependencies')
    except Exception as exc:
        pytest.fail(f'Expected ValueError, but got {type(exc).__name__}: {exc}')
    else:
        pytest.fail('process_logs did not raise ValueError on cyclic dependencies')


def test_mre_log_exists_and_is_absolute_minimal_production_reproducer():
    assert os.path.exists(MRE_PATH), f'File {MRE_PATH} does not exist.'
    with open(MRE_PATH) as f:
        lines = [line.strip() for line in f if line.strip()]

    # Preserve the original size and content assertions.
    assert len(lines) >= 3, 'MRE log must have at least 3 lines to form a cycle and trigger it.'
    assert len(lines) <= 4, 'MRE log should be minimal (<= 4 lines).'
    requires_count = sum(1 for line in lines if ',REQUIRES,' in line)
    completed_count = sum(1 for line in lines if ',COMPLETED' in line)
    assert requires_count >= 2, 'MRE log must contain at least two REQUIRES statements to form a cycle.'
    assert completed_count >= 1, 'MRE log must contain a COMPLETED statement to trigger the resolution.'

    assert os.path.isfile(PRODUCTION_PATH), f'File {PRODUCTION_PATH} does not exist.'
    with open(PRODUCTION_PATH) as f:
        production = [line.strip() for line in f if line.strip()]

    # The MRE must be an order-preserving selection from the supplied production log.
    position = -1
    for line in lines:
        try:
            position = production.index(line, position + 1)
        except ValueError:
            pytest.fail(f'MRE line is not from production_logs.txt in production order: {line!r}')

    assert parsed_trigger_has_reachable_cycle(lines), 'mre_log.txt does not independently describe a triggered dependency cycle.'
    for index in range(len(lines)):
        reduced = lines[:index] + lines[index + 1:]
        assert not parsed_trigger_has_reachable_cycle(reduced), (
            f'mre_log.txt is not absolutely minimal; removing line {index + 1} still reproduces the cycle.'
        )

    module = load_processor()
    assert_expected_cycle_error(module, lines)


def test_log_processor_raises_value_error_on_cycle():
    module = load_processor()
    assert_expected_cycle_error(module, [
        'A,REQUIRES,B',
        'B,REQUIRES,A',
        'A,COMPLETED',
    ])


def test_processor_handles_derived_acyclic_and_varied_cyclic_graphs():
    module = load_processor()
    rng = random.Random(917263)

    # A fake implementation that always raises must fail on valid dependency trees.
    for case in range(12):
        names = [f'VALID_{case}_{rng.randrange(10**9)}_{i}' for i in range(rng.randint(2, 10))]
        lines = [f'{names[i]},REQUIRES,{names[i + 1]}' for i in range(len(names) - 1)]
        lines.append(f'{names[0]},COMPLETED')
        try:
            call_with_timeout(module.process_logs, lines, seconds=2)
        except CallTimedOut:
            pytest.fail('process_logs hung on an acyclic dependency tree')
        except Exception as exc:
            pytest.fail(f'process_logs rejected an acyclic dependency tree: {type(exc).__name__}: {exc}')

    # Exercise independently generated cycles of different sizes and identifiers.
    for case in range(12):
        size = rng.randint(1, 9)
        names = [f'CYCLE_{case}_{rng.randrange(10**9)}_{i}' for i in range(size)]
        cycle_lines = [f'{names[i]},REQUIRES,{names[(i + 1) % size]}' for i in range(size)]
        prefix = [f'DECOY_{case}_{i},REQUIRES,LEAF_{case}_{i}' for i in range(rng.randint(0, 4))]
        trigger = names[rng.randrange(size)]
        assert_expected_cycle_error(module, prefix + cycle_lines + [f'{trigger},COMPLETED'])

    # Merely defining a cycle does not trigger resolution until COMPLETED is processed.
    try:
        call_with_timeout(module.process_logs, ['X,REQUIRES,Y', 'Y,REQUIRES,X'], seconds=2)
    except Exception as exc:
        pytest.fail(f'process_logs raised before dependency resolution was triggered: {type(exc).__name__}: {exc}')


def test_resolve_dependencies_itself_detects_cycles_and_preserves_valid_resolution():
    module = load_processor()
    dependencies = {'root': ['left', 'right'], 'left': ['leaf'], 'right': ['leaf']}
    try:
        result = call_with_timeout(module.resolve_dependencies, 'root', dependencies, seconds=2)
    except Exception as exc:
        pytest.fail(f'resolve_dependencies failed on an acyclic graph: {type(exc).__name__}: {exc}')
    assert result == 5, 'resolve_dependencies must preserve its existing resolved-count behavior on valid graphs.'

    dependencies = {'one': ['two'], 'two': ['three'], 'three': ['one']}
    try:
        call_with_timeout(module.resolve_dependencies, 'one', dependencies, seconds=2)
    except ValueError as exc:
        assert str(exc) == EXPECTED_ERROR, f'Incorrect ValueError message: {exc}'
    except CallTimedOut:
        pytest.fail('resolve_dependencies hung on a cycle')
    except Exception as exc:
        pytest.fail(f'Expected ValueError from resolve_dependencies, got {type(exc).__name__}: {exc}')
    else:
        pytest.fail('resolve_dependencies did not raise ValueError on a cycle')


def run_regression_with_stub(mode, timeout=8):
    temp_dir = tempfile.mkdtemp(prefix='regression_check_')
    try:
        copied_script = os.path.join(temp_dir, 'regression_test.py')
        shutil.copy2(REGRESSION_PATH, copied_script)
        marker = os.path.join(temp_dir, 'called.txt')
        stub = f'''import os\nimport time\n\ndef process_logs(log_lines):\n    lines = [line.strip() for line in log_lines if line.strip()]\n    with open({marker!r}, 'w') as marker_file:\n        marker_file.write('\\n'.join(lines))\n    with open({MRE_PATH!r}) as mre_file:\n        expected = [line.strip() for line in mre_file if line.strip()]\n    if lines != expected:\n        raise RuntimeError('regression test did not pass the contents of mre_log.txt')\n    mode = {mode!r}\n    if mode == 'expected':\n        raise ValueError({EXPECTED_ERROR!r})\n    if mode == 'wrong':\n        raise ValueError('wrong message')\n    if mode == 'hang':\n        time.sleep(30)\n    return None\n'''
        with open(os.path.join(temp_dir, 'log_processor.py'), 'w') as f:
            f.write(stub)
        env = os.environ.copy()
        env['PYTHONPATH'] = temp_dir
        result = subprocess.run(
            [sys.executable, copied_script],
            cwd=temp_dir,
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        called = os.path.exists(marker)
        return result, called
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_regression_test_script_performs_required_test_and_exit_mapping():
    assert os.path.exists(REGRESSION_PATH), f'File {REGRESSION_PATH} does not exist.'

    result, called = run_regression_with_stub('expected')
    assert called, 'regression_test.py did not import log_processor and call process_logs.'
    assert result.returncode == 0, (
        f'regression_test.py exited with code {result.returncode}, expected 0 for the expected ValueError. '
        f'Output: {result.stdout} {result.stderr}'
    )

    result, called = run_regression_with_stub('none')
    assert called, 'regression_test.py did not call process_logs in the no-error scenario.'
    assert result.returncode == 2, (
        f'regression_test.py exited with code {result.returncode}, expected 2 when process_logs completes without error.'
    )

    result, called = run_regression_with_stub('wrong')
    assert called, 'regression_test.py did not call process_logs in the wrong-error scenario.'
    assert result.returncode != 0, 'regression_test.py accepted a ValueError with the wrong message.'

    try:
        result, called = run_regression_with_stub('hang')
    except subprocess.TimeoutExpired:
        pytest.fail('regression_test.py did not enforce its own timeout for a hanging process_logs call.')
    assert called, 'regression_test.py did not call process_logs in the hanging scenario.'
    assert result.returncode == 1, (
        f'regression_test.py exited with code {result.returncode}, expected 1 when process_logs hangs.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
