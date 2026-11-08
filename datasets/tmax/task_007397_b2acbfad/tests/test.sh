#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

ROOT = Path('/home/user/polybuild')
SOURCE = ROOT / 'polygen.cpp'
BINARY = ROOT / 'polygen'
MAKEFILE = ROOT / 'Makefile'
LOG = ROOT / 'build_success.log'


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, timeout=30, **kwargs)


def assert_generated_makefile(path, blocks):
    assert path.is_file(), f'Generator did not create {path}'
    lines = path.read_text().splitlines()
    previous = -1
    for target, dependencies, command in blocks:
        rule = f"{target}:" + (f" {' '.join(dependencies)}" if dependencies else '')
        matches = [i for i, line in enumerate(lines) if line == rule]
        assert len(matches) == 1, f'Expected exactly one rule {rule!r}; generated lines: {lines!r}'
        index = matches[0]
        assert index > previous, 'Targets were not emitted in input order'
        assert index + 1 < len(lines), f'Missing recipe after {rule!r}'
        assert lines[index + 1] == '\t' + command, (
            f'Recipe for {target!r} must immediately follow its rule and begin with one TAB'
        )
        assert '&' not in lines[index], 'Dependency separators were not translated to spaces'
        previous = index


def exercise_generator(executable):
    token = uuid.uuid4().hex
    final = f'final_{token}'
    middle = f'middle_{token}'
    leaf = f'leaf_{token}'
    side = f'side_{token}'

    leaf_marker = f'leaf_{token}.txt'
    side_marker = f'side_{token}.txt'
    middle_marker = f'middle_{token}.txt'
    final_marker = f'final_{token}.txt'

    blocks = [
        (final, [middle, side], f'test -f {middle_marker} && test -f {side_marker} && printf final > {final_marker}'),
        (middle, [leaf], f'test -f {leaf_marker} && printf middle > {middle_marker}'),
        (leaf, [], f'printf leaf > {leaf_marker}'),
        (side, [], f'printf side > {side_marker}'),
    ]

    poly = []
    languages = ['Meta', 'Python', 'C++', 'Meta']
    for (target, dependencies, command), language in zip(blocks, languages):
        poly.extend([
            f'@target {target}',
            '@deps ' + (' & '.join(dependencies) if dependencies else 'none'),
            f'@lang {language}',
            f'@run {command}',
            '',
        ])

    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        input_path = work / f'{token}.poly'
        output_path = work / 'GeneratedMakefile'
        input_path.write_text('\n'.join(poly))

        run([str(executable), str(input_path), str(output_path)], cwd=work)
        assert_generated_makefile(output_path, blocks)
        run(['make', '-f', str(output_path), final], cwd=work)

        assert (work / leaf_marker).read_text() == 'leaf'
        assert (work / side_marker).read_text() == 'side'
        assert (work / middle_marker).read_text() == 'middle'
        assert (work / final_marker).read_text() == 'final'


def test_polygen_cpp_exists():
    assert SOURCE.is_file(), f'Source file {SOURCE} is missing.'


def test_polygen_binary_executable():
    assert BINARY.is_file(), f'Binary file {BINARY} is missing.'
    assert os.access(BINARY, os.X_OK), f'Binary file {BINARY} is not executable.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'polygen must be a compiled native executable.'


def test_makefile_exists():
    assert MAKEFILE.is_file(), f'Generated file {MAKEFILE} is missing.'


def test_generator_behavior_from_binary_and_source():
    exercise_generator(BINARY)

    with tempfile.TemporaryDirectory() as directory:
        rebuilt = Path(directory) / 'polygen-rebuilt'
        run(['g++', '-std=c++17', str(SOURCE), '-o', str(rebuilt)])
        exercise_generator(rebuilt)


def test_build_success_log():
    build_poly = '''@target all
@deps app_bin & test_run
@lang Meta
@run echo "Build complete"

@target app_bin
@deps none
@lang C++
@run g++ src/app.cpp -o app

@target test_run
@deps app_bin
@lang Python
@run python3 tests/verify.py
'''
    app_cpp = '''#include <iostream>
int main() {
    std::cout << "POLYBUILD_APP_OK" << std::endl;
    return 0;
}
'''
    verify_py = '''import subprocess
import sys

try:
    result = subprocess.run(['./app'], capture_output=True, text=True, check=True)
    if "POLYBUILD_APP_OK" in result.stdout:
        with open('/home/user/polybuild/build_success.log', 'w') as f:
            f.write("INTEGRATION_TEST_PASSED\\n")
        print("Test passed.")
    else:
        sys.exit(1)
except Exception as e:
    print(f"Test failed: {e}")
    sys.exit(1)
'''

    (ROOT / 'src').mkdir(exist_ok=True)
    (ROOT / 'tests').mkdir(exist_ok=True)
    (ROOT / 'build.poly').write_text(build_poly)
    (ROOT / 'src/app.cpp').write_text(app_cpp)
    (ROOT / 'tests/verify.py').write_text(verify_py)

    for path in (LOG, ROOT / 'app', MAKEFILE):
        if path.exists() or path.is_symlink():
            path.unlink()

    run([str(BINARY), str(ROOT / 'build.poly'), str(MAKEFILE)], cwd=ROOT)
    run(['make', 'all'], cwd=ROOT)

    assert LOG.is_file(), f"Log file {LOG} is missing. Did 'make all' run successfully?"
    content = LOG.read_text()
    assert 'INTEGRATION_TEST_PASSED' in content, (
        f"Expected 'INTEGRATION_TEST_PASSED' in {LOG}, but found: {content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
