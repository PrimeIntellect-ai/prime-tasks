#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
from pathlib import Path
import random
import re
import subprocess
import uuid

import pytest

ENCODER_DIR = Path('/home/user/artifact_encoder')
SO_PATH = ENCODER_DIR / 'libencoder.so'
MAKEFILE_PATH = ENCODER_DIR / 'Makefile'
SCRIPT_PATH = Path('/home/user/pipeline/process_artifacts.py')
RAW_DIR = Path('/home/user/pipeline/raw_artifacts')
ENC_DIR = Path('/home/user/pipeline/encoded_artifacts')
LOG_PATH = Path('/home/user/pipeline/status.log')


def run_checked(command, **kwargs):
    return subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        **kwargs,
    )


def test_00_build_and_ffi_pipeline():
    assert MAKEFILE_PATH.is_file(), f'Makefile {MAKEFILE_PATH} is missing.'
    makefile = MAKEFILE_PATH.read_text()
    assert re.search(r'-fPIC\b', makefile, re.IGNORECASE), 'Makefile does not use -fPIC.'
    assert re.search(r'-shared\b', makefile), 'Makefile does not use -shared.'

    run_checked(['make', 'clean'], cwd=str(ENCODER_DIR))
    for path in ENCODER_DIR.glob('*.o'):
        path.unlink()
    if SO_PATH.exists() or SO_PATH.is_symlink():
        SO_PATH.unlink()
    run_checked(['make'], cwd=str(ENCODER_DIR))
    assert SO_PATH.is_file(), 'Running make did not create libencoder.so.'

    library = ctypes.CDLL(str(SO_PATH))
    process_data = library.process_data
    process_data.argtypes = [
        ctypes.POINTER(ctypes.c_ubyte),
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_ubyte),
    ]
    process_data.restype = ctypes.c_int
    sample = os.urandom(41)
    input_buffer = (ctypes.c_ubyte * len(sample)).from_buffer_copy(sample)
    output_buffer = (ctypes.c_ubyte * len(sample))()
    processed = process_data(input_buffer, len(sample), output_buffer)
    assert processed == len(sample), 'process_data returned the wrong byte count.'
    assert bytes(output_buffer) == bytes(b ^ 0x42 for b in sample), 'The built library does not encode correctly.'

    assert SCRIPT_PATH.is_file(), f'Python script {SCRIPT_PATH} is missing.'
    source = SCRIPT_PATH.read_text()
    tree = ast.parse(source, filename=str(SCRIPT_PATH))
    ctypes_aliases = set()
    ctypes_callables = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'ctypes':
                    ctypes_aliases.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module == 'ctypes':
            for alias in node.names:
                if alias.name in {'CDLL', 'PyDLL'}:
                    ctypes_callables.add(alias.asname or alias.name)

    def rooted_in_ctypes(node):
        while isinstance(node, ast.Attribute):
            node = node.value
        return isinstance(node, ast.Name) and node.id in ctypes_aliases

    uses_ctypes_loader = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        function = node.func
        if isinstance(function, ast.Name) and function.id in ctypes_callables:
            uses_ctypes_loader = True
        elif isinstance(function, ast.Attribute):
            if function.attr in {'CDLL', 'PyDLL', 'LoadLibrary'} and rooted_in_ctypes(function):
                uses_ctypes_loader = True
    assert uses_ctypes_loader, 'process_artifacts.py does not use ctypes to load a library.'

    original_library = SO_PATH.read_bytes()
    original_mode = SO_PATH.stat().st_mode
    token = uuid.uuid4().hex
    probe_name = f'verifier_probe_{token}.bin'
    probe_path = RAW_DIR / probe_name
    probe_encoded_path = ENC_DIR / f'{probe_name}.enc'
    marker_path = Path(f'/tmp/encoder_called_{token}')
    shim_source = Path(f'/tmp/encoder_shim_{token}.c')
    shim_library = Path(f'/tmp/libencoder_shim_{token}.so')
    mask = random.choice([value for value in range(1, 256) if value != 0x42])
    probe_data = os.urandom(137)

    shim_source.write_text(f'''#include <stdio.h>\nint process_data(const unsigned char* input, int length, unsigned char* output) {{\n    FILE *marker = fopen("{marker_path}", "wb");\n    if (marker) {{ fputs("called", marker); fclose(marker); }}\n    for (int i = 0; i < length; ++i) output[i] = input[i] ^ {mask};\n    return length;\n}}\n''')
    run_checked(['gcc', '-shared', '-fPIC', '-o', str(shim_library), str(shim_source)])

    try:
        SO_PATH.write_bytes(shim_library.read_bytes())
        os.chmod(SO_PATH, original_mode)
        probe_path.write_bytes(probe_data)
        if probe_encoded_path.exists():
            probe_encoded_path.unlink()
        if marker_path.exists():
            marker_path.unlink()

        run_checked(['python3', str(SCRIPT_PATH)], cwd=str(SCRIPT_PATH.parent))
        assert marker_path.is_file(), 'The Python pipeline did not call process_data in libencoder.so.'
        assert probe_encoded_path.is_file(), 'The Python pipeline did not encode a newly added artifact.'
        expected_probe = bytes(value ^ mask for value in probe_data)
        assert probe_encoded_path.read_bytes() == expected_probe, 'The pipeline did not use the bytes produced by the C function.'
        expected_total = sum(path.stat().st_size for path in RAW_DIR.iterdir() if path.is_file())
        assert LOG_PATH.is_file(), 'The pipeline did not create status.log when executed.'
        assert LOG_PATH.read_text().strip() == f'Total bytes processed: {expected_total}'
    finally:
        SO_PATH.write_bytes(original_library)
        os.chmod(SO_PATH, original_mode)
        if probe_path.exists():
            probe_path.unlink()
        if probe_encoded_path.exists():
            probe_encoded_path.unlink()
        for temporary in (marker_path, shim_source, shim_library):
            if temporary.exists():
                temporary.unlink()

    run_checked(['python3', str(SCRIPT_PATH)], cwd=str(SCRIPT_PATH.parent))


def test_shared_library_exists():
    so_path = '/home/user/artifact_encoder/libencoder.so'
    assert os.path.isfile(so_path), f'Shared library {so_path} was not built or does not exist.'


def test_encoded_artifacts():
    raw_dir = '/home/user/pipeline/raw_artifacts'
    enc_dir = '/home/user/pipeline/encoded_artifacts'

    assert os.path.isdir(raw_dir), f'Directory {raw_dir} is missing.'
    assert os.path.isdir(enc_dir), f'Directory {enc_dir} is missing.'

    raw_files = os.listdir(raw_dir)
    assert len(raw_files) > 0, 'No raw artifacts found to verify.'

    for raw_file in raw_files:
        raw_path = os.path.join(raw_dir, raw_file)
        enc_path = os.path.join(enc_dir, raw_file + '.enc')

        assert os.path.isfile(enc_path), f'Encoded artifact {enc_path} is missing.'

        with open(raw_path, 'rb') as f:
            raw_data = f.read()

        with open(enc_path, 'rb') as f:
            enc_data = f.read()

        expected_data = bytes([b ^ 0x42 for b in raw_data])

        assert enc_data == expected_data, f'Encoded data in {enc_path} does not match expected XORed output.'


def test_status_log():
    raw_dir = '/home/user/pipeline/raw_artifacts'
    log_path = '/home/user/pipeline/status.log'

    assert os.path.isfile(log_path), f'Log file {log_path} does not exist.'

    total_bytes = 0
    if os.path.isdir(raw_dir):
        for raw_file in os.listdir(raw_dir):
            raw_path = os.path.join(raw_dir, raw_file)
            if os.path.isfile(raw_path):
                total_bytes += os.path.getsize(raw_path)

    expected_log = f'Total bytes processed: {total_bytes}'

    with open(log_path, 'r') as f:
        actual_log = f.read().strip()

    assert actual_log == expected_log, f"Log file content is incorrect. Expected '{expected_log}', got '{actual_log}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
