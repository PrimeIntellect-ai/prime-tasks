#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import secrets
import shutil
import subprocess


def test_source_and_executable_exist():
    source_path = '/home/user/dataset_processor.c'
    executable_path = '/home/user/dataset_processor'

    assert os.path.isfile(source_path), f"Source file {source_path} is missing."
    assert os.path.isfile(executable_path), f"Executable file {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."


def test_summary_log_content():
    log_path = '/home/user/summary.log'
    assert os.path.isfile(log_path), f"Summary log {log_path} is missing."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = {
        "VALID: alpha.gz",
        "INVALID: beta.gz",
        "INVALID: gamma.gz",
        "VALID: delta.gz"
    }

    assert set(lines) == expected_lines, f"Content of {log_path} does not match expected lines."


def test_processed_files():
    processed_dir = '/home/user/processed'
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} is missing."

    alpha_txt = os.path.join(processed_dir, 'alpha.txt')
    delta_txt = os.path.join(processed_dir, 'delta.txt')
    beta_txt = os.path.join(processed_dir, 'beta.txt')
    gamma_txt = os.path.join(processed_dir, 'gamma.txt')

    assert os.path.isfile(alpha_txt), f"Expected processed file {alpha_txt} is missing."
    assert os.path.isfile(delta_txt), f"Expected processed file {delta_txt} is missing."

    assert not os.path.exists(beta_txt), f"Invalid file {beta_txt} should not have been written."
    assert not os.path.exists(gamma_txt), f"Invalid file {gamma_txt} should not have been written."

    with open(alpha_txt, 'r') as f:
        alpha_content = f.read()
        assert alpha_content.count('\n') == 5, f"{alpha_txt} does not contain exactly 5 newline characters."

    with open(delta_txt, 'r') as f:
        delta_content = f.read()
        assert delta_content.count('\n') == 20, f"{delta_txt} does not contain exactly 20 newline characters."

    with open(alpha_txt, 'rb') as f:
        assert f.read() == gzip.open('/home/user/raw_data/alpha.gz', 'rb').read()
    with open(delta_txt, 'rb') as f:
        assert f.read() == gzip.open('/home/user/raw_data/delta.gz', 'rb').read()


def assert_zlib_c_executable(path):
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{path} is not a compiled ELF executable."

    dynamic = subprocess.run(
        ['readelf', '-d', path], capture_output=True, text=True, timeout=10
    )
    assert dynamic.returncode == 0, dynamic.stderr
    assert re.search(r'libz\.so', dynamic.stdout), f"{path} is not linked with zlib."

    symbols = subprocess.run(
        ['nm', '-D', path], capture_output=True, text=True, timeout=10
    )
    assert symbols.returncode == 0, symbols.stderr
    zlib_calls = re.compile(
        r'\b(gzopen64?|gzdopen|gzread|gzwrite|gzclose|gzerror|inflate(?:Init2?_)?|inflateEnd|uncompress2?)'
    )
    assert zlib_calls.search(symbols.stdout), f"{path} does not import a zlib processing function."


def prepare_and_run(executable):
    token = secrets.token_hex(8)
    names = {
        'first': f'first_{token}.gz',
        'second': f'second_{token}.gz',
        'wrong': f'wrong_{token}.gz',
        'corrupt': f'corrupt_{token}.gz',
        'truncated': f'truncated_{token}.gz',
    }
    first = (f"header-{token}\n" + "a short row\n" + "last row\n").encode()
    second = b''.join(f"record {i} {token}\n".encode() for i in range(7))
    wrong = b"one\ntwo\nthree\n"
    truncated_full = gzip.compress(b"x\ny\nz\n", mtime=1)

    raw = '/home/user/raw_data'
    processed = '/home/user/processed'
    shutil.rmtree(raw, ignore_errors=True)
    shutil.rmtree(processed, ignore_errors=True)
    os.makedirs(raw)
    os.makedirs(processed)

    archives = {
        names['first']: gzip.compress(first, mtime=2),
        names['second']: gzip.compress(second, mtime=3),
        names['wrong']: gzip.compress(wrong, mtime=4),
        names['corrupt']: b'not a gzip stream ' + secrets.token_bytes(31),
        names['truncated']: truncated_full[:-8],
    }
    for name, data in archives.items():
        with open(os.path.join(raw, name), 'wb') as f:
            f.write(data)

    rules = [
        (names['first'], 3),
        (names['wrong'], 9),
        (names['corrupt'], 2),
        (names['second'], 7),
        (names['truncated'], 3),
    ]
    with open('/home/user/rules.conf', 'w') as f:
        for name, count in rules:
            f.write(f"{name}:{count}\n")

    try:
        os.unlink('/home/user/summary.log')
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env['PATH'] = '/nonexistent'
    result = subprocess.run(
        [executable], cwd='/home/user', env=env,
        capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{executable} failed with status {result.returncode}: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    expected_lines = {
        f"VALID: {names['first']}",
        f"INVALID: {names['wrong']}",
        f"INVALID: {names['corrupt']}",
        f"VALID: {names['second']}",
        f"INVALID: {names['truncated']}",
    }
    assert os.path.isfile('/home/user/summary.log')
    with open('/home/user/summary.log') as f:
        actual_lines = [line.rstrip('\n') for line in f]
    assert len(actual_lines) == len(expected_lines)
    assert set(actual_lines) == expected_lines

    expected_outputs = {
        names['first'][:-3] + '.txt': first,
        names['second'][:-3] + '.txt': second,
    }
    assert set(os.listdir(processed)) == set(expected_outputs)
    for filename, expected_content in expected_outputs.items():
        path = os.path.join(processed, filename)
        assert os.path.isfile(path)
        with open(path, 'rb') as f:
            assert f.read() == expected_content


def test_source_uses_zlib_and_program_handles_fresh_inputs():
    source = '/home/user/dataset_processor.c'
    submitted = '/home/user/dataset_processor'
    with open(source, 'r', errors='replace') as f:
        source_text = f.read()
    assert re.search(r'^\s*#\s*include\s*[<"]zlib\.h[>"]', source_text, re.MULTILINE), \
        "The C source does not include zlib.h."

    rebuilt = f"/tmp/dataset_processor_rebuilt_{secrets.token_hex(6)}"
    compile_result = subprocess.run(
        ['gcc', source, '-o', rebuilt, '-lz'],
        capture_output=True, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        f"The submitted C source does not compile with zlib: {compile_result.stderr}"
    )

    assert_zlib_c_executable(submitted)
    assert_zlib_c_executable(rebuilt)
    prepare_and_run(submitted)
    prepare_and_run(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
