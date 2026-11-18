#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile


def hash_djb2(s):
    hash_val = 5381
    for c in s:
        hash_val = ((hash_val << 5) + hash_val) + ord(c)
        hash_val &= 0xFFFFFFFFFFFFFFFF  # emulate 64-bit unsigned long
    return hash_val


def test_deduped_configs_log():
    log_path = '/home/user/deduped_configs.log'
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    expected_entries = [
        "PORT=8080",
        "HOST_NAME=web-server-01",
        "DB_HOST=database.local",
        "DB_PORT=5432",
        "WORKER_THREADS=4",
        "QUEUE_URL=redis://localhost:6379",
        "HOST_NAME=cache-server-01"
    ]

    expected_lines = [f"[{hash_djb2(entry)}] {entry}" for entry in expected_entries]

    with open(log_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Contents of {log_path} do not match the expected output."


def test_pipeline_log():
    log_path = '/home/user/pipeline.log'
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    expected_lines = [
        "DUPLICATE: DB_HOST=database.local",
        "DUPLICATE: DB_PORT=5432",
        "DUPLICATE: QUEUE_URL=redis://localhost:6379"
    ]

    with open(log_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Contents of {log_path} do not match the expected duplicates."


def test_c_source_code_regex():
    src_path = '/home/user/config_tracker.c'
    assert os.path.isfile(src_path), f"Source file {src_path} is missing."

    with open(src_path, 'r') as f:
        code = f.read()

    assert 'regcomp' in code, "The C program must use POSIX regex API 'regcomp'."
    assert 'regexec' in code, "The C program must use POSIX regex API 'regexec'."
    assert '<regex.h>' in code, "The C program must include <regex.h>."


def test_compiled_program_on_additional_inputs():
    submitted = '/home/user/config_tracker'
    source = '/home/user/config_tracker.c'

    assert os.path.isfile(submitted), f"Executable {submitted} is missing."
    assert os.access(submitted, os.X_OK), f"File {submitted} is not executable."
    with open(submitted, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"File {submitted} is not a compiled ELF executable."

    rebuilt = os.path.join(tempfile.mkdtemp(prefix='tracker-build-'), 'config_tracker')
    subprocess.run(
        ['gcc', source, '-o', rebuilt],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )

    tag = secrets.token_hex(8)
    k1 = f'alpha_{tag}'
    k2 = f'beta_{tag}'
    k3 = f'gamma_{tag}'
    k4 = f'delta_{tag}'
    v1 = f'Value-{secrets.token_hex(5)}'
    v2 = f'https://host/{secrets.token_hex(5)}'
    v3 = f'internal space {secrets.token_hex(5)}'
    v4 = f'final-{secrets.token_hex(5)}'
    changed = f'changed-{secrets.token_hex(5)}'

    input_dir = tempfile.mkdtemp(prefix='tracker-input-')
    first = os.path.join(input_dir, 'z_first.conf')
    second = os.path.join(input_dir, 'a_second.conf')
    third = os.path.join(input_dir, 'm_third.conf')

    with open(first, 'w') as f:
        f.write(f"   {k1}   =   {v1}   \n")
        f.write(f" {k2}= {v2} \n")
        f.write(f"  {k1.upper()}={v1}\n")
        f.write("bad-key = ignored\n")
        f.write("    # ignored comment = value\n")
        f.write("\n")

    with open(second, 'w') as f:
        f.write(f" {k3} = {v3}   \n")
        f.write(f" {k2.upper()} =   {v2}\n")
        f.write(f" {k1}={changed} \n")
        f.write("this line has no equals sign\n")

    with open(third, 'w') as f:
        f.write(f"{k3.upper()}={v3}\n")
        f.write(f"    {k4}    =    {v4}    \n")

    normalized = [
        f'{k1.upper()}={v1}',
        f'{k2.upper()}={v2}',
        f'{k3.upper()}={v3}',
        f'{k1.upper()}={changed}',
        f'{k4.upper()}={v4}',
    ]
    duplicates = [
        f'{k1.upper()}={v1}',
        f'{k2.upper()}={v2}',
        f'{k3.upper()}={v3}',
    ]
    expected_deduped = [f'[{hash_djb2(entry)}] {entry}' for entry in normalized]
    expected_pipeline = [f'DUPLICATE: {entry}' for entry in duplicates]

    for executable in (submitted, rebuilt):
        with open('/home/user/deduped_configs.log', 'w') as f:
            f.write('SENTINEL MUST BE OVERWRITTEN\n')
        with open('/home/user/pipeline.log', 'w') as f:
            f.write('SENTINEL MUST BE OVERWRITTEN\n')

        result = subprocess.run(
            [executable, first, second, third],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f'{executable} exited with {result.returncode}: {result.stderr}'
        )

        with open('/home/user/deduped_configs.log', 'r') as f:
            actual_deduped = f.read().splitlines()
        with open('/home/user/pipeline.log', 'r') as f:
            actual_pipeline = f.read().splitlines()

        assert actual_deduped == expected_deduped
        assert actual_pipeline == expected_pipeline
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
