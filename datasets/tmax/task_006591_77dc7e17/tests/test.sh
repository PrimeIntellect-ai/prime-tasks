#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

import pytest
from packaging.version import Version

MERGE_SCRIPT = Path('/home/user/merge_plugins.py')
E2E_SCRIPT = Path('/home/user/run_e2e.sh')
INPUT_DIR = Path('/home/user/inputs')
FINAL_JSON = Path('/home/user/final.json')


def merged_expected(documents):
    merged = {}
    for document in documents:
        for item in document:
            name = item['plugin']
            if name not in merged:
                merged[name] = {
                    'required_version': item['version'],
                    'status': 'active' if item['enabled'] else 'inactive',
                }
            else:
                if Version(item['version']) > Version(merged[name]['required_version']):
                    merged[name]['required_version'] = item['version']
                if item['enabled']:
                    merged[name]['status'] = 'active'
    return {'plugins': {name: merged[name] for name in sorted(merged)}}


def write_documents(directory, documents):
    paths = []
    for index, document in enumerate(documents):
        path = Path(directory) / f'service_{index}.json'
        path.write_text(json.dumps(document), encoding='utf-8')
        paths.append(path)
    return paths


def assert_output(path, expected):
    assert path.is_file(), f'{path} was not generated.'
    with path.open(encoding='utf-8') as handle:
        data = json.load(handle)
    assert data == expected
    assert list(data.get('plugins', {}).keys()) == sorted(data.get('plugins', {}).keys())


def test_merge_plugins_script_exists():
    """Verify that the Python script exists."""
    assert os.path.isfile('/home/user/merge_plugins.py'), "/home/user/merge_plugins.py is missing."


def test_run_e2e_script_exists_and_executable():
    """Verify that the bash script exists and is executable."""
    script_path = '/home/user/run_e2e.sh'
    assert os.path.isfile(script_path), f"{script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."


def test_merge_plugins_on_unseen_inputs_with_both_output_flags():
    token = uuid.uuid4().hex[:10]
    p1, p2, p3 = (f'plugin_{token}_{suffix}' for suffix in ('zeta', 'alpha', 'middle'))
    major = int(token[:2], 16) % 20 + 1
    documents = [
        [
            {'plugin': p1, 'version': f'{major}.5.0-alpha.2', 'enabled': False},
            {'plugin': p2, 'version': '2.9.9', 'enabled': False},
        ],
        [
            {'plugin': p1, 'version': f'{major}.5.0', 'enabled': True},
            {'plugin': p2, 'version': '2.10.0', 'enabled': False},
            {'plugin': p3, 'version': '0.1.0', 'enabled': True},
        ],
        [
            {'plugin': p1, 'version': f'{major}.4.99', 'enabled': False},
            {'plugin': p2, 'version': '1.99.99', 'enabled': False},
        ],
    ]
    expected = merged_expected(documents)

    with tempfile.TemporaryDirectory() as temp_dir:
        paths = write_documents(temp_dir, documents)
        for flag in ('-o', '--output'):
            output = Path(temp_dir) / f'output_{flag.lstrip("-")}.json'
            subprocess.run(
                [sys.executable, str(MERGE_SCRIPT), flag, str(output), *map(str, paths)],
                check=True,
                timeout=20,
            )
            assert_output(output, expected)


def test_run_e2e_executes_merge_script_and_handles_unseen_inputs():
    token = uuid.uuid4().hex
    names = [f'e2e_{token}_{suffix}' for suffix in ('charlie', 'bravo', 'alpha')]
    documents = [
        [
            {'plugin': names[0], 'version': '4.0.0-rc.1', 'enabled': False},
            {'plugin': names[1], 'version': '10.2.0', 'enabled': False},
        ],
        [
            {'plugin': names[0], 'version': '4.0.0', 'enabled': True},
            {'plugin': names[1], 'version': '10.1.99', 'enabled': True},
            {'plugin': names[2], 'version': '1.0.0', 'enabled': False},
        ],
    ]
    expected = merged_expected(documents)

    backup_inputs = Path(f'/home/user/inputs.verifier-backup-{token}')
    real_script = Path(f'/home/user/merge_plugins.verifier-real-{token}.py')
    marker = Path(f'/tmp/merge_plugins_called_{token}.json')

    INPUT_DIR.rename(backup_inputs)
    INPUT_DIR.mkdir()
    input_paths = write_documents(INPUT_DIR, documents)
    MERGE_SCRIPT.rename(real_script)

    wrapper = f'''#!/usr/bin/env python3
import json, os, sys
with open({str(marker)!r}, 'w', encoding='utf-8') as handle:
    json.dump({{"argv": sys.argv[1:], "cwd": os.getcwd()}}, handle)
os.execv(sys.executable, [sys.executable, {str(real_script)!r}, *sys.argv[1:]])
'''
    MERGE_SCRIPT.write_text(wrapper, encoding='utf-8')
    MERGE_SCRIPT.chmod(0o755)

    alternate_error = None
    try:
        if FINAL_JSON.exists():
            FINAL_JSON.unlink()
        try:
            subprocess.run([str(E2E_SCRIPT)], check=True, timeout=20)
            assert_output(FINAL_JSON, expected)
            assert marker.is_file(), 'run_e2e.sh did not execute /home/user/merge_plugins.py.'

            invocation = json.loads(marker.read_text(encoding='utf-8'))
            argv = invocation['argv']
            cwd = Path(invocation['cwd'])
            output_value = None
            positional = []
            index = 0
            while index < len(argv):
                arg = argv[index]
                if arg in ('-o', '--output'):
                    assert index + 1 < len(argv), 'Output flag had no value.'
                    output_value = argv[index + 1]
                    index += 2
                elif arg.startswith('--output='):
                    output_value = arg.split('=', 1)[1]
                    index += 1
                else:
                    positional.append(arg)
                    index += 1

            assert output_value is not None, 'run_e2e.sh did not pass an output flag.'
            output_path = Path(output_value)
            if not output_path.is_absolute():
                output_path = cwd / output_path
            assert output_path.resolve() == FINAL_JSON.resolve()

            actual_inputs = set()
            for value in positional:
                path = Path(value)
                if not path.is_absolute():
                    path = cwd / path
                actual_inputs.add(path.resolve())
            assert actual_inputs == {path.resolve() for path in input_paths}, \
                'run_e2e.sh did not pass every JSON input file to merge_plugins.py.'
        except BaseException as exc:
            alternate_error = exc
    finally:
        if MERGE_SCRIPT.exists():
            MERGE_SCRIPT.unlink()
        real_script.rename(MERGE_SCRIPT)
        shutil.rmtree(INPUT_DIR, ignore_errors=True)
        backup_inputs.rename(INPUT_DIR)
        marker.unlink(missing_ok=True)
        subprocess.run([str(E2E_SCRIPT)], check=True, timeout=20)

    if alternate_error is not None:
        raise alternate_error


def test_final_json_exists():
    """Verify that final.json was generated."""
    assert os.path.isfile('/home/user/final.json'), "/home/user/final.json is missing. Did the script run?"


def test_final_json_content_and_sorting():
    """Verify the content and key sorting of final.json."""
    with open('/home/user/final.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/final.json is not valid JSON.")

    expected = {
        "plugins": {
            "auth": {
                "required_version": "1.2.0",
                "status": "active"
            },
            "cache": {
                "required_version": "1.0.0",
                "status": "active"
            },
            "db": {
                "required_version": "2.1.0",
                "status": "active"
            },
            "ui": {
                "required_version": "3.0.0",
                "status": "inactive"
            }
        }
    }

    assert data == expected, "The contents of /home/user/final.json do not match the expected merged output."

    # Verify alphabetical sorting of plugins
    plugins = data.get("plugins", {})
    plugin_keys = list(plugins.keys())
    assert plugin_keys == sorted(plugin_keys), "The plugins in final.json are not sorted alphabetically by name."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
