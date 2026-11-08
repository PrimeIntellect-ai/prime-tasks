#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import uuid
from pathlib import Path

HOME = Path('/home/user')
RAW = HOME / 'raw_metrics.csv'
C_SOURCE = HOME / 'impute_loc.c'
SCRIPT = HOME / 'run_pipeline.sh'
CLEAN = HOME / 'clean_metrics.csv'
LOG = HOME / 'pipeline.log'
BINARY = HOME / 'impute_loc'

ORIGINAL_INPUT = """1672531200,es-ES,ui.button.save,15
1672531260,es-ES,ui.button.save,
1672531320,es-ES,ui.button.save,20
1672531200,fr-FR,ui.button.cancel,
1672531260,fr-FR,ui.button.cancel,5
1672531320,fr-FR,ui.button.cancel,
1672531200,es-ES,ui.menu.file,10
1672531260,es-ES,ui.menu.file,
1672531320,es-ES,ui.button.save,
"""

ORIGINAL_EXPECTED = """1672531200,es-ES,ui.button.save,15
1672531260,es-ES,ui.button.save,15
1672531320,es-ES,ui.button.save,20
1672531200,fr-FR,ui.button.cancel,0
1672531260,fr-FR,ui.button.cancel,5
1672531320,fr-FR,ui.button.cancel,5
1672531200,es-ES,ui.menu.file,10
1672531260,es-ES,ui.menu.file,10
1672531320,es-ES,ui.button.save,20
"""


def expected_locf(text):
    last = {}
    output = []
    for line in text.splitlines():
        timestamp, locale, string_id, count = line.split(',')
        key = (locale, string_id)
        if count == '':
            value = last.get(key, '0')
        else:
            value = count
            last[key] = value
        output.append(','.join((timestamp, locale, string_id, value)))
    return '\n'.join(output) + '\n'


def read(path):
    return path.read_text()


def run_pipeline():
    return subprocess.run(
        [str(SCRIPT)], cwd=str(HOME), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )


def assert_output(expected):
    assert CLEAN.exists(), f'File {CLEAN} does not exist.'
    assert CLEAN.is_file(), f'{CLEAN} is not a file.'
    assert read(CLEAN).strip() == expected.strip(), \
        f'Content of {CLEAN} does not match the expected final state.'


def assert_log_contains(*messages):
    assert LOG.exists(), f'File {LOG} does not exist.'
    assert LOG.is_file(), f'{LOG} is not a file.'
    content = read(LOG)
    for message in messages:
        assert message in content, f'Log file missing message: {message}'


def test_complete_pipeline_and_program():
    assert C_SOURCE.exists(), f'C program {C_SOURCE} does not exist.'
    assert C_SOURCE.is_file(), f'{C_SOURCE} is not a file.'
    assert SCRIPT.exists(), f'Script {SCRIPT} does not exist.'
    assert SCRIPT.is_file(), f'{SCRIPT} is not a file.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'

    source_backup = C_SOURCE.read_bytes()
    raw_backup = RAW.read_bytes() if RAW.exists() else None
    direct_binary = Path('/tmp/impute_loc_verified')

    try:
        # Preserve the original fixed-fixture assertions, but obtain the files by
        # actually running the requested wrapper.
        RAW.write_text(ORIGINAL_INPUT)
        for path in (CLEAN, LOG, BINARY):
            if path.exists() or path.is_symlink():
                path.unlink()
        result = run_pipeline()
        assert result.returncode == 0, \
            f'Pipeline failed on the original input: {result.stdout}{result.stderr}'
        assert_output(ORIGINAL_EXPECTED)
        assert_log_contains('[INFO] Starting localization metrics pipeline',
                            '[SUCCESS] Clean metrics generated')
        assert BINARY.exists(), 'Pipeline did not create impute_loc.'
        assert BINARY.is_file(), 'impute_loc is not a regular file.'
        assert os.access(BINARY, os.X_OK), 'impute_loc is not executable.'
        assert BINARY.read_bytes()[:4] == b'\x7fELF', \
            'impute_loc is not a compiled executable.'

        # Exercise the wrapper on an unpredictable, interleaved fixture.
        token = uuid.uuid4().hex[:10]
        locale_a = 'loc-' + token
        locale_b = 'other-' + token
        string_a = 'ui.dynamic.' + token
        string_b = 'msg.dynamic.' + token
        dynamic_input = '\n'.join([
            f'1900000000,{locale_a},{string_a},',
            f'1900000001,{locale_b},{string_a},31',
            f'1900000002,{locale_a},{string_b},7',
            f'1900000003,{locale_a},{string_a},12',
            f'1900000004,{locale_b},{string_a},',
            f'1900000005,{locale_a},{string_b},',
            f'1900000006,{locale_a},{string_a},',
            f'1900000007,{locale_b},{string_b},',
            f'1900000008,{locale_b},{string_b},44',
            f'1900000009,{locale_b},{string_b},',
        ]) + '\n'
        RAW.write_text(dynamic_input)
        if CLEAN.exists():
            CLEAN.unlink()
        if BINARY.exists():
            BINARY.unlink()
        result = run_pipeline()
        assert result.returncode == 0, \
            f'Pipeline failed on dynamic input: {result.stdout}{result.stderr}'
        assert_output(expected_locf(dynamic_input))
        assert BINARY.exists() and BINARY.read_bytes()[:4] == b'\x7fELF', \
            'Pipeline did not compile impute_loc as an executable.'

        # Independently compile and execute the submitted C source on another
        # generated fixture, proving the C artifact itself implements LOCF.
        compile_result = subprocess.run(
            ['gcc', str(C_SOURCE), '-o', str(direct_binary)],
            cwd=str(HOME), text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=20
        )
        assert compile_result.returncode == 0, \
            f'impute_loc.c does not compile: {compile_result.stderr}'
        token2 = uuid.uuid4().hex[:10]
        direct_input = '\n'.join([
            f'2000000100,x-{token2},key.one,5',
            f'2000000101,y-{token2},key.one,',
            f'2000000102,x-{token2},key.one,',
            f'2000000103,x-{token2},key.two,',
            f'2000000104,y-{token2},key.one,19',
            f'2000000105,x-{token2},key.two,8',
            f'2000000106,y-{token2},key.one,',
            f'2000000107,x-{token2},key.two,',
        ]) + '\n'
        RAW.write_text(direct_input)
        if CLEAN.exists():
            CLEAN.unlink()
        direct_result = subprocess.run(
            [str(direct_binary)], cwd=str(HOME), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert direct_result.returncode == 0, \
            f'Compiled C program failed: {direct_result.stdout}{direct_result.stderr}'
        assert_output(expected_locf(direct_input))

        # A compilation failure must be detected, logged, and returned as failure.
        C_SOURCE.write_text('this is intentionally invalid C source\n')
        for path in (LOG, BINARY):
            if path.exists():
                path.unlink()
        result = run_pipeline()
        assert result.returncode != 0, 'Pipeline reported success after compilation failed.'
        assert_log_contains('[INFO] Starting localization metrics pipeline',
                            '[ERROR] Pipeline failed')

        # A successfully compiled program that exits nonzero must likewise fail.
        C_SOURCE.write_text('int main(void) { return 9; }\n')
        for path in (LOG, BINARY):
            if path.exists():
                path.unlink()
        result = run_pipeline()
        assert result.returncode != 0, 'Pipeline reported success after execution failed.'
        assert BINARY.exists() and BINARY.read_bytes()[:4] == b'\x7fELF', \
            'Pipeline did not compile the replacement C program.'
        assert_log_contains('[INFO] Starting localization metrics pipeline',
                            '[ERROR] Pipeline failed')
        assert '[SUCCESS] Clean metrics generated' not in read(LOG), \
            'Pipeline logged success after the C program failed.'
    finally:
        C_SOURCE.write_bytes(source_backup)
        if raw_backup is None:
            if RAW.exists():
                RAW.unlink()
        else:
            RAW.write_bytes(raw_backup)
        if direct_binary.exists():
            direct_binary.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
