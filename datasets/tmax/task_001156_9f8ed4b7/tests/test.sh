#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import uuid
import pytest

PROCESS = Path('/home/user/process.py')
DATA = Path('/home/user/data.json')
LIB = Path('/home/user/libfilter.so')
RESULT = Path('/home/user/result.json')


def test_process_is_python_and_configures_pipeline():
    """Ensure the requested implementation exists and contains the required ABI/encoding steps."""
    assert PROCESS.is_file(), '/home/user/process.py is missing.'
    source = PROCESS.read_text(encoding='utf-8')
    try:
        tree = ast.parse(source, filename=str(PROCESS))
        compile(tree, str(PROCESS), 'exec')
    except (SyntaxError, ValueError) as exc:
        pytest.fail(f'/home/user/process.py is not valid Python: {exc}')

    constants = {
        node.value.lower()
        for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    }
    assert 'utf-16-le' in constants or 'utf-16le' in constants, 'process.py must decode the base64 bytes as UTF-16-LE.'
    assert 'utf-8' in constants or 'utf8' in constants, 'process.py must re-encode decoded text as UTF-8 for C.'

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            value = node.value
            for target in targets:
                if isinstance(target, ast.Attribute) and target.attr in ('argtypes', 'restype'):
                    base = target.value
                    if isinstance(base, ast.Attribute) and base.attr == 'check_valid_api':
                        assignments[target.attr] = value

    assert 'argtypes' in assignments, 'Set lib.check_valid_api.argtypes.'
    assert 'restype' in assignments, 'Set lib.check_valid_api.restype.'
    arg_names = {node.attr for node in ast.walk(assignments['argtypes']) if isinstance(node, ast.Attribute)}
    restype_names = {node.attr for node in ast.walk(assignments['restype']) if isinstance(node, ast.Attribute)}
    assert 'c_char_p' in arg_names, 'check_valid_api.argtypes must use ctypes.c_char_p.'
    assert 'c_int' in restype_names, 'check_valid_api.restype must use ctypes.c_int.'


def test_process_executes_decoding_and_shared_library_pipeline():
    """Run process.py with unpredictable UTF-16 data and a temporary probe implementation."""
    assert DATA.is_file(), '/home/user/data.json is missing.'
    assert LIB.is_file(), '/home/user/libfilter.so is missing.'

    marker = 'PROBE_' + uuid.uuid4().hex
    first_id = 200000 + secrets.randbelow(100000)
    second_id = 400000 + secrets.randbelow(100000)
    third_id = 600000 + secrets.randbelow(100000)
    records = [
        {'id': first_id, 'payload': base64.b64encode(('前' + marker + '雪').encode('utf-16-le')).decode('ascii')},
        {'id': second_id, 'payload': base64.b64encode(('API_VALID_' + uuid.uuid4().hex).encode('utf-16-le')).decode('ascii')},
        {'id': third_id, 'payload': base64.b64encode((marker + '_尾').encode('utf-16-le')).decode('ascii')},
    ]

    with tempfile.TemporaryDirectory() as temp_dir:
        temp = Path(temp_dir)
        data_backup = temp / 'data.json.backup'
        lib_backup = temp / 'libfilter.so.backup'
        probe_source = temp / 'probe.c'
        probe_lib = temp / 'libfilter.so'
        shutil.copy2(DATA, data_backup)
        shutil.copy2(LIB, lib_backup)
        probe_source.write_text(
            '#include <string.h>\n'
            'int check_valid_api(const char *input) {\n'
            '  if (input == 0) return 0;\n'
            f'  return strstr(input, "{marker}") != 0 ? 1 : 0;\n'
            '}\n',
            encoding='utf-8'
        )
        subprocess.run(
            ['gcc', '-shared', '-fPIC', '-o', str(probe_lib), str(probe_source)],
            check=True,
            capture_output=True,
            text=True,
        )

        final_run = None
        try:
            DATA.write_text(json.dumps(records), encoding='utf-8')
            shutil.copy2(probe_lib, LIB)
            run = subprocess.run(
                ['python3', str(PROCESS)],
                cwd='/home/user',
                capture_output=True,
                text=True,
                timeout=15,
            )
            assert run.returncode == 0, f'process.py failed on probe data:\nstdout: {run.stdout}\nstderr: {run.stderr}'
            assert RESULT.is_file(), 'process.py did not create /home/user/result.json.'
            try:
                probe_results = json.loads(RESULT.read_text(encoding='utf-8'))
            except json.JSONDecodeError as exc:
                pytest.fail(f'process.py wrote invalid JSON for probe data: {exc}')
            assert probe_results == [first_id, third_id], (
                'process.py did not correctly decode UTF-16-LE, re-encode UTF-8, and invoke check_valid_api.'
            )
        finally:
            shutil.copy2(data_backup, DATA)
            shutil.copy2(lib_backup, LIB)
            final_run = subprocess.run(
                ['python3', str(PROCESS)],
                cwd='/home/user',
                capture_output=True,
                text=True,
                timeout=15,
            )

        assert final_run.returncode == 0, (
            f'process.py failed on the original data:\nstdout: {final_run.stdout}\nstderr: {final_run.stderr}'
        )


def test_result_json_exists():
    """Test that result.json has been created."""
    assert os.path.isfile('/home/user/result.json'), '/home/user/result.json does not exist. Did you execute process.py?'


def test_result_json_content():
    """Test that result.json contains the correct filtered IDs."""
    with open('/home/user/result.json', 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('/home/user/result.json is not a valid JSON file.')

    assert isinstance(results, list), '/home/user/result.json must contain a JSON array.'
    assert results == [101, 103], f'Expected IDs [101, 103], but got {results}. Check your decoding logic and ctypes ABI definitions.'


def test_data_json_unmodified():
    """Test that data.json was not modified."""
    assert os.path.isfile('/home/user/data.json'), '/home/user/data.json is missing.'
    with open('/home/user/data.json', 'r') as f:
        content = f.read()
    assert 'QQBQAEkAXwBWAEEATABJAEQAXwBUAEUAUwBUAA==' in content, 'data.json was modified.'
    assert 'SQBOAFYAQQBMAEkARABfAEQAQQBUAEEA' in content, 'data.json was modified.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
