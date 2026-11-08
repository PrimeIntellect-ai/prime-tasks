#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import stat
import subprocess
import tempfile


def get_sha256(filepath):
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def test_manifest_csv_exists_and_correct():
    manifest_path = '/home/user/manifest.csv'
    assert os.path.isfile(manifest_path), f"File {manifest_path} is missing"

    artifacts_dir = '/home/user/artifacts'
    expected_lines = []

    for filename in os.listdir(artifacts_dir):
        filepath = os.path.join(artifacts_dir, filename)
        if filename.endswith('.bin') and os.path.isfile(filepath):
            st = os.stat(filepath)
            if st.st_mode & stat.S_IXUSR:
                size = st.st_size
                checksum = get_sha256(filepath)
                expected_lines.append(f"{filename},{size},{checksum}\n")

    expected_lines.sort()

    with open(manifest_path, 'r') as f:
        actual_lines = f.readlines()

    assert actual_lines == expected_lines, "Initial manifest.csv does not contain the correct sorted entries"


def test_clean_manifest_compiled():
    executable_path = '/home/user/clean_manifest'
    assert os.path.isfile(executable_path), f"Compiled executable {executable_path} is missing"
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable"
    with open(executable_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{executable_path} is not a compiled ELF executable"


def make_filter_case():
    nonce = secrets.token_hex(8)
    names = [
        f'alpha_{nonce}.bin',
        f'beta_debug_{nonce}.bin',
        f'gamma_{nonce}.bin',
        f'debug_{nonce}.bin',
        f'omega_{nonce}.bin',
        f'nodebug_{nonce}.bin',
    ]
    lines = [f"{name},{i + 17},{secrets.token_hex(32)}\n" for i, name in enumerate(names)]
    payload = ''.join(lines).encode('ascii')
    expected = ''.join(line for line, name in zip(lines, names) if 'debug' not in name).encode('ascii')
    return payload, expected


def assert_filter_works(executable, payload, expected):
    result = subprocess.run(
        [executable], input=payload, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5
    )
    assert result.returncode == 0, (
        f"{executable} failed on a multi-line manifest with exit code "
        f"{result.returncode}: {result.stderr.decode(errors='replace')}"
    )
    assert result.stdout == expected, f"{executable} did not correctly filter the supplied manifest"


def test_clean_manifest_c_fixed():
    c_file_path = '/home/user/clean_manifest.c'
    assert os.path.isfile(c_file_path), f"Source file {c_file_path} is missing"

    with open(c_file_path, 'r') as f:
        content = f.read()
    assert content.strip(), f"Source file {c_file_path} is empty"

    payload, expected = make_filter_case()

    # Exercise the submitted compiled artifact directly on verifier-generated data.
    assert_filter_works('/home/user/clean_manifest', payload, expected)

    # Independently compile the submitted source and exercise that build too. This
    # verifies that the source itself contains a working fix for the multi-line bug.
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, 'clean_manifest')
        compile_result = subprocess.run(
            ['gcc', '-std=gnu11', c_file_path, '-o', rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        assert compile_result.returncode == 0, (
            "clean_manifest.c does not compile: "
            + compile_result.stderr.decode(errors='replace')
        )
        assert_filter_works(rebuilt, payload, expected)


def test_final_manifest_csv_correct():
    final_manifest_path = '/home/user/final_manifest.csv'
    assert os.path.isfile(final_manifest_path), f"File {final_manifest_path} is missing"

    artifacts_dir = '/home/user/artifacts'
    expected_lines = []

    for filename in os.listdir(artifacts_dir):
        filepath = os.path.join(artifacts_dir, filename)
        if filename.endswith('.bin') and os.path.isfile(filepath):
            st = os.stat(filepath)
            if st.st_mode & stat.S_IXUSR and "debug" not in filename:
                size = st.st_size
                checksum = get_sha256(filepath)
                expected_lines.append(f"{filename},{size},{checksum}\n")

    expected_lines.sort()

    with open(final_manifest_path, 'r') as f:
        actual_lines = f.readlines()

    assert actual_lines == expected_lines, "final_manifest.csv does not contain the correct filtered entries"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
