#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess
import tempfile

CPP_PATH = '/home/user/upload_server.cpp'
BINARY_PATH = '/home/user/upload_server'
REPORT_PATH = '/home/user/security_report.txt'
KEYS_PATH = '/home/user/.ssh/authorized_keys'


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(65536), b''):
            h.update(chunk)
    return h.hexdigest()


def binary_symbols(path):
    result = subprocess.run(
        ['nm', '--defined-only', path],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    symbols = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if fields:
            symbols.append(fields[-1])
    return symbols


def save_uploaded_file_symbols(path):
    return [
        symbol for symbol in binary_symbols(path)
        if symbol.startswith('_Z')
        and 'save_uploaded_file' in symbol
        and '.' not in symbol
    ]


def test_authorized_keys_hardened():
    path = KEYS_PATH
    assert os.path.isfile(path), f"{path} is missing"
    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    for line in lines:
        assert not line.startswith('ssh-rsa'), "ssh-rsa key found in authorized_keys"

    assert len(lines) == 2, f"Expected exactly 2 keys in authorized_keys, found {len(lines)}"


def test_compiled_binary_exists_is_elf_and_matches_source():
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is missing"
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable"

    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{BINARY_PATH} is not an ELF binary"

    subprocess.run(
        ['readelf', '-h', BINARY_PATH],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'upload_server')
        subprocess.run(
            ['g++', '-O2', CPP_PATH, '-o', rebuilt],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert sha256_file(BINARY_PATH) == sha256_file(rebuilt), \
            "The submitted binary does not match g++ -O2 compilation of upload_server.cpp"

    symbols = save_uploaded_file_symbols(BINARY_PATH)
    assert len(symbols) == 1, \
        f"Expected exactly one defined save_uploaded_file mangled symbol, found {symbols}"

    os.makedirs('/var/uploads', exist_ok=True)
    result = subprocess.run(
        [BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, \
        f"Compiled upload_server exited with status {result.returncode}"


def test_upload_server_cpp_fixed():
    path = CPP_PATH
    assert os.path.isfile(path), f"{path} is missing"
    with open(path, 'r') as f:
        content = f.read()

    assert 'void save_uploaded_file(std::string filename)' in content, "Function signature changed or missing"
    assert '..' in content, "Missing check for '..'"
    assert '/' in content or "'/'" in content or '"/"' in content, "Missing check for '/'"

    token = 'verifier_' + secrets.token_hex(12)
    traversal_target = os.path.join('/var', token + '_escape')
    slash_parent = os.path.join('/var/uploads', token + '_dir')
    slash_target = os.path.join(slash_parent, 'blocked.bin')
    valid_target = os.path.join('/var/uploads', token + '_valid.bin')

    for target in (traversal_target, slash_target, valid_target):
        if os.path.isdir(target):
            shutil.rmtree(target)
        elif os.path.exists(target):
            os.remove(target)
    os.makedirs('/var/uploads', exist_ok=True)
    os.makedirs(slash_parent, exist_ok=True)

    with tempfile.TemporaryDirectory() as td:
        obj = os.path.join(td, 'upload_server.o')
        harness_cpp = os.path.join(td, 'harness.cpp')
        harness = os.path.join(td, 'harness')
        with open(harness_cpp, 'w') as f:
            f.write('''#include <string>\nvoid save_uploaded_file(std::string filename);\nint main(int argc, char **argv) {\n    if (argc != 2) return 2;\n    save_uploaded_file(std::string(argv[1]));\n    return 0;\n}\n''')

        subprocess.run(
            ['g++', '-O2', '-Dmain=upload_server_original_main', '-c', CPP_PATH, '-o', obj],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        subprocess.run(
            ['g++', '-O2', harness_cpp, obj, '-o', harness],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )

        for bad_name in ('../' + token + '_escape', token + '_dir/blocked.bin'):
            result = subprocess.run(
                [harness, bad_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert result.returncode == 0, f"Harness failed for input {bad_name!r}"

        assert not os.path.exists(traversal_target), \
            "save_uploaded_file wrote a file for a filename containing '..'"
        assert not os.path.exists(slash_target), \
            "save_uploaded_file wrote a file for a filename containing '/'"

        valid_name = token + '_valid.bin'
        result = subprocess.run(
            [harness, valid_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, "Harness failed for a valid filename"
        assert os.path.isfile(valid_target), \
            "save_uploaded_file no longer saves valid filenames"
        with open(valid_target, 'rb') as f:
            assert f.read() == b'data', "Valid upload did not retain the original behavior"

    shutil.rmtree(slash_parent, ignore_errors=True)
    if os.path.exists(valid_target):
        os.remove(valid_target)


def test_security_report():
    report_path = REPORT_PATH
    cpp_path = CPP_PATH

    assert os.path.isfile(report_path), f"{report_path} is missing"
    assert os.path.isfile(cpp_path), f"{cpp_path} is missing"

    with open(cpp_path, 'rb') as f:
        cpp_hash = hashlib.sha256(f.read()).hexdigest()

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f.readlines()]

    assert len(lines) == 3, f"Expected exactly 3 lines in security_report.txt, found {len(lines)}"

    mangled_name = lines[0]
    assert 'save_uploaded_file' in mangled_name and mangled_name.startswith('_Z'), f"Line 1 does not look like a mangled symbol for save_uploaded_file: {mangled_name}"

    symbols = save_uploaded_file_symbols(BINARY_PATH)
    assert len(symbols) == 1, \
        f"Expected exactly one defined save_uploaded_file mangled symbol, found {symbols}"
    assert mangled_name == symbols[0], \
        f"Line 1 is not the exact symbol extracted from the binary. Expected {symbols[0]}, got {mangled_name}"

    assert lines[1] == cpp_hash, f"Line 2 (SHA256) is incorrect. Expected {cpp_hash}, got {lines[1]}"

    assert lines[2] == '2', f"Line 3 (key count) is incorrect. Expected '2', got {lines[2]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
