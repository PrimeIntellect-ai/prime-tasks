#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

PROJECT_DIR = Path('/home/user/project')
PATCH_FILE = PROJECT_DIR / 'Makefile.patch'
SCRIPT_FILE = PROJECT_DIR / 'build_and_run.sh'
RESULT_FILE = Path('/home/user/result.txt')

ORIGINAL_MAKEFILE = '''app: main.o compute.o message.pb-c.o
\tgcc -o app main.o compute.o message.pb-c.o -lprotobuf-c

main.o: main.c compute.h compute.o
\tgcc -c main.c

compute.o: compute.c compute.h main.o
\tgcc -c compute.c

message.pb-c.o: message.pb-c.c message.pb-c.h
\tgcc -c message.pb-c.c
'''

MESSAGE_PROTO = '''syntax = "proto3";
message MathResult {
  int32 value = 1;
}
'''

COMPUTE_H = '''#ifndef COMPUTE_H
#define COMPUTE_H
int compute_sum_of_squares(int n);
#endif
'''

COMPUTE_C = '''#include "compute.h"
int compute_sum_of_squares(int n) {
    int sum = 0;
    for (int i = 1; i <= n; i++) {
        sum += i * i;
    }
    return sum;
}
'''

MAIN_C = '''#include <stdio.h>
#include <stdlib.h>
#include "compute.h"
#include "message.pb-c.h"

int main() {
    MathResult msg = MATH_RESULT__INIT;
    msg.value = compute_sum_of_squares(10);
    printf("Result: %d\\n", msg.value);
    return 0;
}
'''


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=30, **kwargs)


def assert_fixed_makefile(path):
    text = Path(path).read_text()
    rules = {}
    for line in text.splitlines():
        if not line or line[0].isspace() or line.lstrip().startswith('#') or ':' not in line:
            continue
        target, prerequisites = line.split(':', 1)
        rules[target.strip()] = prerequisites.split()

    expected = {
        'main.o': {'main.c', 'compute.h'},
        'compute.o': {'compute.c', 'compute.h'},
        'message.pb-c.o': {'message.pb-c.c', 'message.pb-c.h'},
    }
    for target, required in expected.items():
        assert target in rules, f'Missing Makefile rule for {target}'
        prerequisites = rules[target]
        assert required.issubset(prerequisites), f'{target} is missing required source/header dependencies'
        assert not any(item.endswith('.o') for item in prerequisites), \
            f'{target} still depends on an object file: {prerequisites}'


def test_makefile_patch_exists():
    assert PATCH_FILE.is_file(), f"Patch file '{PATCH_FILE}' does not exist."


def test_build_and_run_script_exists_and_executable():
    assert SCRIPT_FILE.is_file(), f"Script file '{SCRIPT_FILE}' does not exist."
    assert os.access(SCRIPT_FILE, os.X_OK), f"Script file '{SCRIPT_FILE}' is not executable."


def test_result_file_content():
    assert RESULT_FILE.is_file(), f"Result file '{RESULT_FILE}' does not exist."
    content = RESULT_FILE.read_text().strip()
    expected_content = 'Result: 385'
    assert expected_content in content, \
        f"Result file '{RESULT_FILE}' does not contain expected output. Found: '{content}'"


def test_patch_and_script_rebuild_real_project():
    patch_text = PATCH_FILE.read_text()
    headers = []
    for line in patch_text.splitlines():
        if line.startswith('--- ') or line.startswith('+++ '):
            name = line[4:].split('\t', 1)[0].split(' ', 1)[0]
            headers.append(name)
            assert name in ('Makefile', 'a/Makefile', 'b/Makefile'), \
                f'Patch modifies an unexpected path: {name}'
    assert headers, 'Makefile.patch is empty or is not a standard unified patch'

    # Verify independently that the submitted patch transforms the original Makefile.
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        (td_path / 'Makefile').write_text(ORIGINAL_MAKEFILE)
        local_patch = td_path / 'Makefile.patch'
        local_patch.write_text(patch_text)
        strip = '1' if any(name.startswith(('a/', 'b/')) for name in headers) else '0'
        with local_patch.open('rb') as patch_input:
            subprocess.run(['patch', '--batch', '--forward', '-p' + strip], cwd=td,
                           stdin=patch_input, check=True, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=10)
        assert_fixed_makefile(td_path / 'Makefile')

    # Restore the supplied project inputs and remove every output that could have
    # been fabricated before running the utility.
    inputs = {
        'Makefile': ORIGINAL_MAKEFILE,
        'message.proto': MESSAGE_PROTO,
        'compute.h': COMPUTE_H,
        'compute.c': COMPUTE_C,
        'main.c': MAIN_C,
    }
    for name, content in inputs.items():
        path = PROJECT_DIR / name
        path.write_text(content)
        os.chown(path, 1000, 1000)

    for name in ('message.pb-c.c', 'message.pb-c.h', 'main.o', 'compute.o',
                 'message.pb-c.o', 'app'):
        path = PROJECT_DIR / name
        if path.exists() or path.is_symlink():
            path.unlink()
    if RESULT_FILE.exists() or RESULT_FILE.is_symlink():
        RESULT_FILE.unlink()

    run(['runuser', '-u', 'user', '--', str(SCRIPT_FILE)], cwd=PROJECT_DIR,
        env={**os.environ, 'HOME': '/home/user'})

    # Keep the original final-state assertions and strengthen them with real artifacts.
    assert PATCH_FILE.is_file()
    assert SCRIPT_FILE.is_file() and os.access(SCRIPT_FILE, os.X_OK)
    assert RESULT_FILE.is_file()
    content = RESULT_FILE.read_text().strip()
    assert 'Result: 385' in content
    assert content == 'Result: 385'

    for name in ('message.pb-c.c', 'message.pb-c.h', 'main.o', 'compute.o',
                 'message.pb-c.o', 'app'):
        assert (PROJECT_DIR / name).is_file(), f'{name} was not generated by the script'
    assert (PROJECT_DIR / 'app').read_bytes()[:4] == b'\x7fELF', 'app is not an ELF executable'
    assert os.access(PROJECT_DIR / 'app', os.X_OK), 'app is not executable'

    # Generated protobuf files must be the actual protoc-c output for message.proto.
    with tempfile.TemporaryDirectory() as td:
        Path(td, 'message.proto').write_text(MESSAGE_PROTO)
        run(['protoc-c', '--c_out=.', 'message.proto'], cwd=td)
        for name in ('message.pb-c.c', 'message.pb-c.h'):
            assert (PROJECT_DIR / name).read_bytes() == Path(td, name).read_bytes(), \
                f'{name} is not the expected protoc-c output'

    # Inputs must remain intact, while the installed Makefile must contain the fix.
    for name, content in inputs.items():
        if name != 'Makefile':
            assert (PROJECT_DIR / name).read_text() == content, f'{name} was improperly modified'
    assert_fixed_makefile(PROJECT_DIR / 'Makefile')

    # Force a fresh compilation through the patched Makefile, then independently
    # execute the resulting binary and compare it with the script's result.
    for name in ('main.o', 'compute.o', 'message.pb-c.o', 'app'):
        (PROJECT_DIR / name).unlink()
    run(['make'], cwd=PROJECT_DIR)
    rebuilt = PROJECT_DIR / 'app'
    assert rebuilt.read_bytes()[:4] == b'\x7fELF'
    expected_value = sum(i * i for i in range(1, 11))
    expected_output = f'Result: {expected_value}\n'
    actual_output = run(['./app'], cwd=PROJECT_DIR).stdout
    assert actual_output == expected_output
    assert RESULT_FILE.read_text() == expected_output
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
