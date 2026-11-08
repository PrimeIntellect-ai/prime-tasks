#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
MAKEFILE = HOME / 'Makefile'
SOURCE = HOME / 'schema_gen.c'
EXECUTABLE = HOME / 'schema_gen'
B64_FILE = HOME / 'legacy.b64'
JSON_FILE = HOME / 'migrated_schema.json'

EXPECTED_DATA = [
    {'id': 101, 'username': 'alice', 'joined_date': '2021-01-01', 'active': True},
    {'id': 102, 'username': 'bob', 'joined_date': '2022-02-02', 'active': True},
]


def run_make(timeout=30, check=True):
    return subprocess.run(
        ['make', '-B', '-f', str(MAKEFILE)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=check,
    )


def remove_outputs():
    for path in (EXECUTABLE, B64_FILE, JSON_FILE):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def test_makefile_exists():
    makefile_path = '/home/user/Makefile'
    assert os.path.exists(makefile_path), f'Makefile is missing at {makefile_path}.'
    assert os.path.isfile(makefile_path), f'{makefile_path} is not a file.'


def test_schema_gen_executable_exists():
    executable_path = '/home/user/schema_gen'
    assert os.path.exists(executable_path), f'Executable {executable_path} is missing.'
    assert os.path.isfile(executable_path), f'{executable_path} is not a file.'
    assert os.access(executable_path, os.X_OK), f'{executable_path} is not executable.'


def test_legacy_b64_exists():
    b64_path = '/home/user/legacy.b64'
    assert os.path.exists(b64_path), f'Base64 output file {b64_path} is missing.'
    assert os.path.isfile(b64_path), f'{b64_path} is not a file.'


def test_migrated_schema_json():
    json_path = '/home/user/migrated_schema.json'
    assert os.path.exists(json_path), f'Migrated JSON file {json_path} is missing.'
    assert os.path.isfile(json_path), f'{json_path} is not a file.'

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {json_path} does not contain valid JSON.')

    assert data == EXPECTED_DATA, f'The contents of {json_path} do not match the expected migrated schema.'


def test_makefile_rebuilds_and_runs_real_pipeline():
    original_source = SOURCE.read_bytes()
    original_mode = SOURCE.stat().st_mode

    try:
        # A forced build from absent outputs must recreate the complete requested pipeline.
        remove_outputs()
        result = run_make()

        assert EXECUTABLE.is_file(), 'make did not create /home/user/schema_gen.'
        assert os.access(EXECUTABLE, os.X_OK), 'schema_gen produced by make is not executable.'
        assert EXECUTABLE.read_bytes()[:4] == b'\x7fELF', 'schema_gen is not a compiled executable.'
        assert B64_FILE.is_file(), 'make did not create /home/user/legacy.b64.'
        assert JSON_FILE.is_file(), 'make did not create /home/user/migrated_schema.json.'

        generated = subprocess.run(
            [str(EXECUTABLE)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=10, check=True
        ).stdout
        assert B64_FILE.read_bytes() == generated, 'legacy.b64 is not the output of schema_gen.'

        encoded = B64_FILE.read_bytes()
        try:
            decoded = base64.b64decode(encoded, validate=True)
        except Exception as exc:
            pytest.fail(f'legacy.b64 is not valid Base64: {exc}')
        assert decoded == (
            b'USER_ID|USER_NAME|CREATED_AT\n'
            b'101|alice|2021-01-01\n'
            b'102|bob|2022-02-02\n'
        )
        assert json.loads(JSON_FILE.read_text()) == EXPECTED_DATA

        # Confirm that the build plan invokes a separate script stored in /home/user.
        known = {'Makefile', 'schema_gen.c', 'schema_gen', 'legacy.b64', 'migrated_schema.json'}
        candidates = [
            p for p in HOME.iterdir()
            if p.name not in known and not p.name.startswith('.') and p.is_file()
        ]
        dry_run = subprocess.run(
            ['make', '-n', '-B', '-f', str(MAKEFILE)], cwd=str(HOME),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            timeout=20, check=True
        ).stdout
        referenced_scripts = [
            p for p in candidates
            if str(p) in dry_run or p.name in dry_run
        ]
        assert referenced_scripts, 'The Makefile does not invoke a migration script stored in /home/user.'

        # Replace the generator input with unpredictable records and force another full build.
        # Expected JSON is derived here from the generated tabular input, so fixed output cannot pass.
        records = [
            (secrets.randbelow(800000) + 1000, 'user_' + secrets.token_hex(6), '2031-03-14'),
            (secrets.randbelow(800000) + 900000, 'user_' + secrets.token_hex(6), '2042-11-09'),
            (secrets.randbelow(800000) + 1800000, 'user_' + secrets.token_hex(6), '2050-07-22'),
        ]
        tabular = 'USER_ID|USER_NAME|CREATED_AT\n' + ''.join(
            f'{uid}|{name}|{date}\n' for uid, name, date in records
        )
        alternate_b64 = base64.b64encode(tabular.encode('utf-8')).decode('ascii')
        SOURCE.write_text(
            '#include <stdio.h>\n'
            'int main(void) {\n'
            f'    printf("{alternate_b64}\\n");\n'
            '    return 0;\n'
            '}\n'
        )
        remove_outputs()
        run_make()

        assert EXECUTABLE.read_bytes()[:4] == b'\x7fELF', 'Alternate build did not compile schema_gen.c.'
        generated = subprocess.run(
            [str(EXECUTABLE)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=10, check=True
        ).stdout
        assert B64_FILE.read_bytes() == generated, 'Makefile did not save the rebuilt generator output.'
        assert base64.b64decode(B64_FILE.read_bytes(), validate=True).decode('utf-8') == tabular

        expected_dynamic = [
            {'id': uid, 'username': name, 'joined_date': date, 'active': True}
            for uid, name, date in records
        ]
        with JSON_FILE.open() as f:
            dynamic_data = json.load(f)
        assert dynamic_data == expected_dynamic, 'The migration does not transform the generated input records.'
        assert all(type(item['id']) is int for item in dynamic_data), 'Migrated ids must be integers.'
        assert all(item['active'] is True for item in dynamic_data), 'Migrated active fields must be true booleans.'

    finally:
        SOURCE.write_bytes(original_source)
        os.chmod(SOURCE, original_mode)
        remove_outputs()
        subprocess.run(
            ['make', '-B', '-f', str(MAKEFILE)], cwd=str(HOME),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
