#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT = Path('/home/user/project')
EXPECTED_OUTPUT = (
    'Application: MyApp\n'
    'Port: 8080\n'
    'Database Host: localhost\n'
    'Database User: admin'
)


def run(cmd, **kwargs):
    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        **kwargs,
    )


def test_success_out_content():
    success_file = '/home/user/project/build/success.out'
    assert os.path.isfile(success_file), f'Expected output file {success_file} does not exist.'

    with open(success_file, 'r') as f:
        content = f.read().strip()

    expected_output = (
        'Application: MyApp\n'
        'Port: 8080\n'
        'Database Host: localhost\n'
        'Database User: admin'
    )

    assert content == expected_output, f'File {success_file} content does not match the expected output.'


def test_config_h_valid():
    config_h_file = '/home/user/project/build/config.h'
    assert os.path.isfile(config_h_file), f'Generated header {config_h_file} does not exist.'

    with open(config_h_file, 'r') as f:
        lines = f.readlines()

    for line in lines:
        if line.startswith('#define'):
            parts = line.strip().split()
            assert len(parts) >= 2, f'Invalid #define in {config_h_file}: {line}'
            macro_name = parts[1]
            assert macro_name != '#', f'Comment line was not ignored in {config_h_file}: {line}'
            assert macro_name != '""', f'Empty line was not ignored in {config_h_file}: {line}'


def test_codegen_logic_updated():
    codegen_file = '/home/user/project/src/codegen.cpp'
    assert os.path.isfile(codegen_file), f'File {codegen_file} does not exist.'

    with open(codegen_file, 'r') as f:
        content = f.read()

    has_hash_check = "('#')" in content or '"#"' in content or "'#'" in content
    has_empty_check = (
        'empty()' in content
        or 'length() == 0' in content
        or 'size() == 0' in content
        or 'pos == std::string::npos' in content
        or 'find_first_not_of' in content
    )

    assert has_hash_check or has_empty_check, 'codegen.cpp does not appear to contain logic to skip comments or empty lines.'


def test_build_script_and_application_really_work():
    build_script = PROJECT / 'build.sh'
    assert build_script.is_file(), 'build.sh is missing.'

    result = run([str(build_script)], cwd=str(PROJECT))
    assert result.returncode == 0, f'build.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'

    codegen = PROJECT / 'build/codegen'
    app = PROJECT / 'build/app'
    config_h = PROJECT / 'build/config.h'
    assert codegen.is_file() and os.access(codegen, os.X_OK), 'build.sh did not produce an executable codegen tool.'
    assert app.is_file() and os.access(app, os.X_OK), 'build.sh did not produce an executable application.'
    assert config_h.is_file(), 'build.sh did not generate build/config.h.'

    app_result = run([str(app)], cwd=str(PROJECT))
    assert app_result.returncode == 0, f'Built application failed: {app_result.stderr}'
    assert app_result.stdout.strip() == EXPECTED_OUTPUT, 'Built application output is incorrect.'

    success_out = PROJECT / 'build/success.out'
    assert success_out.read_text().strip() == app_result.stdout.strip(), 'success.out is not the output of the built application.'

    with tempfile.TemporaryDirectory() as td:
        rebuilt_app = Path(td) / 'app'
        compile_result = run(
            ['g++', str(PROJECT / 'src/main.cpp'), '-o', str(rebuilt_app)],
            cwd=str(PROJECT),
        )
        assert compile_result.returncode == 0, f'main.cpp does not compile with the generated header:\n{compile_result.stderr}'
        rebuilt_result = run([str(rebuilt_app)])
        assert rebuilt_result.returncode == 0
        assert rebuilt_result.stdout.strip() == EXPECTED_OUTPUT


def test_codegen_ignores_empty_and_indented_comment_lines_on_unseen_inputs():
    source = PROJECT / 'src/codegen.cpp'
    assert source.is_file()

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        codegen = td / 'codegen'
        compile_result = run(['g++', '-std=c++11', str(source), '-o', str(codegen)])
        assert compile_result.returncode == 0, f'codegen.cpp does not compile:\n{compile_result.stderr}'

        for case in range(3):
            token = secrets.token_hex(8).upper()
            entries = {
                f'ALPHA_{token}': secrets.token_hex(6),
                f'BETA_{token}': secrets.token_hex(7),
                f'GAMMA_{token}': secrets.token_hex(5),
            }
            input_file = td / f'input_{case}.txt'
            output_file = td / f'config_{case}.h'
            input_file.write_text(
                f'\n'
                f'   # indented comment {secrets.token_hex(5)}\n'
                f'{next(iter(entries))}={next(iter(entries.values()))}\n'
                f'   \n'
                f'\t# tab-indented comment {secrets.token_hex(5)}\n'
                f'{list(entries)[1]}={list(entries.values())[1]}\n'
                f'# ordinary comment {secrets.token_hex(5)}\n'
                f'\t \t\n'
                f'{list(entries)[2]}={list(entries.values())[2]}\n'
                f'\n'
            )

            generate_result = run([str(codegen), str(input_file), str(output_file)])
            assert generate_result.returncode == 0, f'codegen failed on valid input:\n{generate_result.stderr}'
            assert output_file.is_file(), 'codegen did not create its requested output file.'

            generated = output_file.read_text()
            define_names = re.findall(r'^#define\s+([A-Za-z_][A-Za-z0-9_]*)\b', generated, re.MULTILINE)
            assert define_names == list(entries), 'Generated header contains missing, extra, or reordered definitions.'

            probe = td / f'probe_{case}.cpp'
            probe_bin = td / f'probe_{case}'
            include_path = str(output_file).replace('\\', '\\\\').replace('"', '\\"')
            body = ['#include <iostream>', f'#include "{include_path}"', 'int main() {']
            for key in entries:
                body.append(f'  std::cout << {key} << "\\n";')
            body.append('  return 0;')
            body.append('}')
            probe.write_text('\n'.join(body) + '\n')

            probe_compile = run(['g++', '-std=c++11', str(probe), '-o', str(probe_bin)])
            assert probe_compile.returncode == 0, f'Generated header is not valid C++:\n{probe_compile.stderr}\nHeader:\n{generated}'
            probe_result = run([str(probe_bin)])
            assert probe_result.returncode == 0
            assert probe_result.stdout.splitlines() == list(entries.values()), 'Generated macros have incorrect values.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
