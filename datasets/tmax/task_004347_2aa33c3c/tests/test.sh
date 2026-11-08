#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import struct
import random
import subprocess
import tempfile
from pathlib import Path


def generate_fuzz_input(filename, length):
    with open(filename, 'wb') as f:
        # Native byte order matches the C reference on this container.
        f.write(struct.pack('4sI', b'SENS', length))
        if length > 0:
            floats = [random.uniform(-1e6, 1e6) for _ in range(length)]
            f.write(struct.pack(f'{length}d', *floats))


def test_make_and_logging_configuration():
    """The repaired Makefile must run its tests and provide CALC_LOG_DIR."""
    project = Path('/app/calc_core-1.2.3')
    makefile = project / 'Makefile'
    assert makefile.is_file(), 'Makefile is missing.'

    marker_fd, marker_name = tempfile.mkstemp(prefix='calc_make_marker_')
    os.close(marker_fd)
    os.unlink(marker_name)
    injected_test = project / 'test_verifier_build.py'
    backup = injected_test.read_bytes() if injected_test.exists() else None

    injected_test.write_text(
        "import os\n"
        "import unittest\n"
        "\n"
        "class BuildConfigurationTest(unittest.TestCase):\n"
        "    def test_logging_configuration(self):\n"
        "        log_dir = os.environ.get('CALC_LOG_DIR')\n"
        "        self.assertTrue(log_dir, 'CALC_LOG_DIR was not defined by make')\n"
        "        from calc_core import config\n"
        "        self.assertEqual(config.LOG_DIR, log_dir)\n"
        "        os.makedirs(log_dir, exist_ok=True)\n"
        "        self.assertTrue(os.path.isdir(log_dir))\n"
        "        with open(os.environ['BUILD_MARKER'], 'w') as f:\n"
        "            f.write('ran')\n"
    )

    env = os.environ.copy()
    env.pop('CALC_LOG_DIR', None)
    env['PYTHONPATH'] = str(project)
    env['BUILD_MARKER'] = marker_name
    try:
        proc = subprocess.run(
            ['make', 'test'], cwd=str(project), env=env,
            capture_output=True, text=True, timeout=120
        )
    finally:
        if backup is None:
            injected_test.unlink(missing_ok=True)
        else:
            injected_test.write_bytes(backup)

    assert proc.returncode == 0, (
        f"make test failed with return code {proc.returncode}:\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.isfile(marker_name), (
        "make test did not execute the package's discovered tests"
    )
    os.unlink(marker_name)


def test_fuzz_equivalence():
    """Verify that the Python program matches the C oracle bit-exactly."""
    random.seed(42)
    oracle = '/app/bin/legacy_calc_ref'
    assert os.path.isfile(oracle), 'Oracle binary not found.'

    agent_cmd = ['python', '-m', 'calc_core.cli']
    agent_env = os.environ.copy()
    agent_env['PYTHONPATH'] = '/app/calc_core-1.2.3'
    agent_env['CALC_LOG_DIR'] = '/tmp'

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            if i == 0:
                length = 0
            elif i == 1:
                length = 1
            else:
                length = random.randint(2, 10000)

            input_file = os.path.join(tmpdir, f'test_{i}.bin')
            generate_fuzz_input(input_file, length)

            oracle_proc = subprocess.run(
                [oracle, input_file], capture_output=True, text=True
            )
            agent_proc = subprocess.run(
                agent_cmd + [input_file], env=agent_env,
                capture_output=True, text=True
            )

            assert agent_proc.returncode == oracle_proc.returncode, (
                f"Return code mismatch on input {i} (length {length}): "
                f"agent={agent_proc.returncode}, oracle={oracle_proc.returncode}\n"
                f"Agent stderr: {agent_proc.stderr}\n"
                f"Oracle stderr: {oracle_proc.stderr}"
            )
            assert agent_proc.stdout == oracle_proc.stdout, (
                f"Output mismatch on input {i} (length {length}):\n"
                f"Agent output:\n{agent_proc.stdout}\n"
                f"Oracle output:\n{oracle_proc.stdout}"
            )


def test_regression_script():
    """Require a real precision-triggering input and logged calc_core execution."""
    script_path = Path('/home/user/regression.py')
    test_bin = Path('/home/user/test.bin')
    log_txt = Path('/home/user/regression_log.txt')
    math_ops = Path('/app/calc_core-1.2.3/calc_core/math_ops.py')
    assert script_path.is_file(), f'{script_path} does not exist.'
    assert math_ops.is_file(), f'{math_ops} does not exist.'

    test_bin.unlink(missing_ok=True)
    log_txt.unlink(missing_ok=True)

    # Temporarily instrument the required reduction function so merely touching
    # the requested files cannot satisfy the regression-script requirement.
    marker_fd, marker_name = tempfile.mkstemp(prefix='calc_regression_marker_')
    os.close(marker_fd)
    os.unlink(marker_name)
    original_math_ops = math_ops.read_bytes()
    instrumentation = (
        "\n# verifier runtime instrumentation\n"
        "_verifier_original_calc_variance = calc_variance\n"
        "def calc_variance(data):\n"
        f"    with open({marker_name!r}, 'a') as _verifier_marker:\n"
        "        _verifier_marker.write('called\\n')\n"
        "    return _verifier_original_calc_variance(data)\n"
    ).encode()

    env = os.environ.copy()
    env['PYTHONPATH'] = '/app/calc_core-1.2.3'
    env['CALC_LOG_DIR'] = '/tmp'
    try:
        math_ops.write_bytes(original_math_ops + instrumentation)
        proc = subprocess.run(
            ['python', str(script_path)], env=env,
            capture_output=True, text=True, timeout=120
        )
    finally:
        math_ops.write_bytes(original_math_ops)

    assert proc.returncode == 0, (
        f"regression.py failed with return code {proc.returncode}:\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert test_bin.is_file(), f'regression.py did not create {test_bin}.'
    assert log_txt.is_file(), f'regression.py did not create {log_txt}.'
    assert os.path.isfile(marker_name), (
        'regression.py did not execute calc_core.math_ops.calc_variance'
    )
    os.unlink(marker_name)

    raw = test_bin.read_bytes()
    assert len(raw) >= 8, 'test.bin is too short to contain a valid header.'
    signature, length = struct.unpack('4sI', raw[:8])
    assert signature == b'SENS', 'test.bin has an invalid signature.'
    assert 2 <= length <= 1_000_000, (
        'test.bin must contain a nontrivial, bounded precision regression case.'
    )
    assert len(raw) == 8 + length * 8, (
        'test.bin payload size does not match its length field.'
    )
    values = struct.unpack(f'{length}d', raw[8:])
    assert all(x == x and abs(x) != float('inf') for x in values), (
        'test.bin contains non-finite values.'
    )

    oracle_proc = subprocess.run(
        ['/app/bin/legacy_calc_ref', str(test_bin)],
        capture_output=True, text=True, timeout=120
    )
    assert oracle_proc.returncode == 0, (
        f'Generated regression input was rejected by the oracle: {oracle_proc.stderr}'
    )

    n = len(values)
    naive = sum(x ** 2 for x in values) / n - (sum(values) / n) ** 2
    naive_output = f'{naive:.17g}\n'
    assert naive_output != oracle_proc.stdout, (
        'Generated input does not trigger the original naive-sum precision bug.'
    )

    agent_proc = subprocess.run(
        ['python', '-m', 'calc_core.cli', str(test_bin)], env=env,
        capture_output=True, text=True, timeout=120
    )
    assert agent_proc.returncode == oracle_proc.returncode
    assert agent_proc.stdout == oracle_proc.stdout, (
        'calc_core does not match the oracle on the generated regression input.'
    )

    log = log_txt.read_text(errors='replace')
    expected_output = oracle_proc.stdout.strip()
    assert expected_output and expected_output in log, (
        'regression_log.txt does not contain calc_core output.'
    )
    status_re = re.compile(
        r'(?i)(?:\b(?:status|return\s*code|returncode|exit(?:\s*code)?)\b'
        r'[^\r\n]{0,40}\b(?:0|ok|success|successful|passed)\b|'
        r'\b(?:success|successful|passed)\b)'
    )
    assert status_re.search(log), (
        'regression_log.txt does not record a successful status/exit result.'
    )


def test_no_byte_identical_oracle_in_submission():
    oracle = Path('/app/bin/legacy_calc_ref')
    oracle_bytes = oracle.read_bytes()
    candidates = list(Path('/app/calc_core-1.2.3').rglob('*'))
    candidates.append(Path('/home/user/regression.py'))
    for candidate in candidates:
        if candidate.is_file() and candidate.stat().st_size == len(oracle_bytes):
            assert candidate.read_bytes() != oracle_bytes, (
                f'Submitted artifact is byte-identical to the reference: {candidate}'
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
