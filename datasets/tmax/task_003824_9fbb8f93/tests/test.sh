#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shlex
import stat
import subprocess
import tempfile

import pytest


def test_process_asset_sh_fixed():
    """Verify the script really invokes wc with the spaced filename as one argument."""
    script_path = '/home/user/build_env/process_asset.sh'
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with tempfile.TemporaryDirectory() as tmpdir:
        test_file = os.path.join(tmpdir, 'test file with spaces.txt')
        marker = os.path.join(tmpdir, 'wc-called')
        fake_bin = os.path.join(tmpdir, 'bin')
        os.mkdir(fake_bin)

        with open(test_file, 'w') as f:
            f.write('hello world')

        fake_wc = os.path.join(fake_bin, 'wc')
        with open(fake_wc, 'w') as f:
            f.write(f'''#!/bin/bash
if [ "$#" -ne 2 ] || [ "$1" != "-c" ] || [ "$2" != "$EXPECTED_ASSET" ]; then
    exit 91
fi
if [ ! -f "$2" ] || [ "$(cat "$2")" != "hello world" ]; then
    exit 92
fi
printf 'called' > "$WC_MARKER"
exit 0
''')
        os.chmod(fake_wc, 0o755)

        env = os.environ.copy()
        env['PATH'] = fake_bin + os.pathsep + env.get('PATH', '')
        env['EXPECTED_ASSET'] = test_file
        env['WC_MARKER'] = marker
        result = subprocess.run(
            [script_path, test_file], capture_output=True, text=True, env=env
        )

        assert result.returncode == 0, (
            'process_asset.sh failed when processing a file with spaces. '
            f'Error: {result.stderr}'
        )
        assert os.path.isfile(marker), (
            'process_asset.sh returned success without actually invoking wc on the asset.'
        )


def test_regression_script_exists_and_runs():
    """Verify creation, subprocess execution, exit-code assertion, and cleanup."""
    regression_path = '/home/user/build_env/test_regression.py'
    process_path = '/home/user/build_env/process_asset.sh'
    dummy_file = '/home/user/build_env/mock data file.txt'

    assert os.path.isfile(regression_path), (
        f"Regression test script {regression_path} is missing."
    )

    with open(regression_path, 'r') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=regression_path)
    except SyntaxError as exc:
        pytest.fail(f'test_regression.py is not valid Python: {exc}')

    imports_subprocess = any(
        isinstance(node, ast.Import)
        and any(alias.name == 'subprocess' for alias in node.names)
        for node in ast.walk(tree)
    )
    calls_subprocess = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == 'subprocess'
        for node in ast.walk(tree)
    )
    has_assert = any(isinstance(node, ast.Assert) for node in ast.walk(tree))
    assert imports_subprocess, 'test_regression.py must import subprocess.'
    assert calls_subprocess, 'test_regression.py must call a subprocess function.'
    assert has_assert, 'test_regression.py must assert the process exit code.'

    assert os.path.isfile(process_path), f"Script {process_path} is missing."
    with open(process_path, 'rb') as f:
        original_process = f.read()
    original_mode = stat.S_IMODE(os.stat(process_path).st_mode)

    with tempfile.TemporaryDirectory() as tmpdir:
        marker = os.path.join(tmpdir, 'process-called')
        probe = f'''#!/bin/bash
if [ "$#" -ne 1 ] || [ "$1" != "mock data file.txt" ]; then
    exit 93
fi
if [ ! -f "/home/user/build_env/mock data file.txt" ]; then
    exit 94
fi
printf 'called' > {shlex.quote(marker)}
exit "${{REGRESSION_PROBE_EXIT:-0}}"
'''

        try:
            with open(process_path, 'w') as f:
                f.write(probe)
            os.chmod(process_path, 0o755)

            if os.path.exists(dummy_file):
                os.remove(dummy_file)

            result = subprocess.run(
                ['python3', regression_path],
                capture_output=True,
                text=True,
                cwd='/home/user/build_env',
            )
            assert result.returncode == 0, (
                'test_regression.py failed during its success case. Output: '
                f'{result.stderr or result.stdout}'
            )
            assert os.path.isfile(marker), (
                'test_regression.py did not invoke process_asset.sh with the required file.'
            )
            assert not os.path.exists(dummy_file), (
                "test_regression.py did not clean up 'mock data file.txt'."
            )

            os.remove(marker)
            failure_env = os.environ.copy()
            failure_env['REGRESSION_PROBE_EXIT'] = '17'
            failed_result = subprocess.run(
                ['python3', regression_path],
                capture_output=True,
                text=True,
                cwd='/home/user/build_env',
                env=failure_env,
            )
            assert os.path.isfile(marker), (
                'test_regression.py did not execute process_asset.sh in the failure case.'
            )
            assert failed_result.returncode != 0, (
                'test_regression.py did not assert that process_asset.sh returned exit code 0.'
            )
        finally:
            if os.path.exists(dummy_file):
                os.remove(dummy_file)
            with open(process_path, 'wb') as f:
                f.write(original_process)
            os.chmod(process_path, original_mode)


def test_report_json_correct():
    """Verify that report.json exists and contains the correct findings."""
    report_path = '/home/user/report.json'
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {report_path} is not valid JSON.")

    assert 'failed_uri_from_pcap' in report_data, (
        "Key 'failed_uri_from_pcap' is missing in report.json."
    )
    assert 'server_log_timestamp' in report_data, (
        "Key 'server_log_timestamp' is missing in report.json."
    )
    assert report_data['failed_uri_from_pcap'] == '/data%20file.csv', (
        "Incorrect failed_uri_from_pcap. Expected '/data%20file.csv', got "
        f"'{report_data['failed_uri_from_pcap']}'."
    )
    assert report_data['server_log_timestamp'] == 1700000005, (
        'Incorrect server_log_timestamp. Expected 1700000005, got '
        f"'{report_data['server_log_timestamp']}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
