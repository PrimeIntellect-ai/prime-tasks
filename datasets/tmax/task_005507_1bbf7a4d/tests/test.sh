#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import posixpath
import secrets
import subprocess
import tempfile

import pytest

ANALYZER_DIR = pathlib.Path('/home/user/analyzer')
PAYLOADS_PATH = pathlib.Path('/home/user/payloads.txt')
LOG_PATH = pathlib.Path('/home/user/escapes.log')
BASE_DIR = '/var/www/uploads'


def decode_payload(hex_str: str) -> str:
    """Decodes the hex payload using the XOR key 0x5A."""
    try:
        raw_bytes = bytes.fromhex(hex_str)
        return bytes([b ^ 0x5A for b in raw_bytes]).decode('utf-8')
    except Exception as e:
        pytest.fail(f'Failed to decode payload {hex_str} during test setup: {e}')


def resolve_path(decoded_str: str) -> str:
    """Resolves the path relative to the simulated sandbox directory."""
    clean_str = decoded_str.lstrip('/')
    return posixpath.normpath(posixpath.join(BASE_DIR, clean_str))


def expected_lines(payloads):
    result = []
    base_dir_prefix = BASE_DIR + '/'
    for payload in payloads:
        decoded = decode_payload(payload)
        resolved = resolve_path(decoded)
        if not (resolved == BASE_DIR or resolved.startswith(base_dir_prefix)):
            result.append(f'{payload} -> {decoded} -> {resolved}')
    return result


def assert_log_matches(payloads):
    assert LOG_PATH.is_file(), f'Output file {LOG_PATH} is missing. Did you run your analyzer?'
    with LOG_PATH.open('r') as f:
        actual_log_lines = [line.strip() for line in f if line.strip()]
    wanted = expected_lines(payloads)
    assert actual_log_lines == wanted, (
        f'Contents of {LOG_PATH} do not match the expected output.\n'
        f'Expected:\n' + '\n'.join(wanted) + '\n\n'
        f'Actual:\n' + '\n'.join(actual_log_lines)
    )


def build_rust_analyzer():
    assert ANALYZER_DIR.is_dir(), f'{ANALYZER_DIR} is missing.'
    rust_sources = sorted(ANALYZER_DIR.rglob('*.rs'))
    assert rust_sources, f'No Rust source files were found under {ANALYZER_DIR}.'

    manifest = ANALYZER_DIR / 'Cargo.toml'
    build_dir = pathlib.Path(tempfile.mkdtemp(prefix='analyzer-build-'))

    if manifest.is_file():
        proc = subprocess.run(
            ['cargo', 'build', '--manifest-path', str(manifest),
             '--target-dir', str(build_dir), '--message-format=json'],
            cwd=ANALYZER_DIR, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=120
        )
        assert proc.returncode == 0, f'Rust analyzer failed to compile with Cargo:\n{proc.stderr}'
        executables = []
        for line in proc.stdout.splitlines():
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if (message.get('reason') == 'compiler-artifact'
                    and 'bin' in message.get('target', {}).get('kind', [])
                    and message.get('executable')):
                executables.append(message['executable'])
        executables = list(dict.fromkeys(executables))
        assert len(executables) == 1, (
            'The Cargo project must build one unambiguous analyzer binary; '
            f'found {len(executables)} binaries.'
        )
        executable = pathlib.Path(executables[0])
    else:
        preferred = [ANALYZER_DIR / 'main.rs', ANALYZER_DIR / 'src' / 'main.rs']
        entrypoints = [p for p in preferred if p.is_file()]
        if not entrypoints and len(rust_sources) == 1:
            entrypoints = rust_sources
        assert len(entrypoints) == 1, (
            'A non-Cargo submission must have one clear Rust entry point '
            '(main.rs or src/main.rs).'
        )
        executable = build_dir / 'analyzer'
        proc = subprocess.run(
            ['rustc', '--edition=2021', str(entrypoints[0]), '-o', str(executable)],
            cwd=ANALYZER_DIR, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=120
        )
        assert proc.returncode == 0, f'Rust analyzer failed to compile:\n{proc.stderr}'

    assert executable.is_file() and os.access(executable, os.X_OK), (
        'Compilation did not produce an executable analyzer.'
    )
    return executable


def run_analyzer(executable, payloads):
    PAYLOADS_PATH.write_text('\n'.join(payloads) + '\n')
    if LOG_PATH.exists():
        LOG_PATH.unlink()
    proc = subprocess.run(
        [str(executable)], cwd=ANALYZER_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert proc.returncode == 0, (
        f'Analyzer exited with status {proc.returncode}.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    assert_log_matches(payloads)


def encode_for_test(text: str) -> str:
    return bytes(b ^ 0x5A for b in text.encode('utf-8')).hex()


def test_escapes_log_correctness_and_rust_execution():
    assert PAYLOADS_PATH.is_file(), f'Input file {PAYLOADS_PATH} is missing.'
    original_payload_bytes = PAYLOADS_PATH.read_bytes()
    original_payloads = [line.strip() for line in original_payload_bytes.decode().splitlines() if line.strip()]
    executable = build_rust_analyzer()

    try:
        # Preserve the original verifier's exact fixed-input output assertion,
        # but require the compiled Rust artifact to generate the file first.
        run_analyzer(executable, original_payloads)

        nonce = secrets.token_hex(8)
        dynamic_plaintexts = [
            f'images/./{nonce}/../safe.txt',
            f'../outside-{nonce}.txt',
            f'a/b/../../inside-{nonce}.txt',
            f'../../../../etc/{nonce}',
            f'../uploads_evil/{nonce}',
            f'/nested/../safe-{nonce}.txt',
        ]
        dynamic_payloads = [encode_for_test(value) for value in dynamic_plaintexts]
        run_analyzer(executable, dynamic_payloads)

        # Leave the required output corresponding to the supplied payload file.
        run_analyzer(executable, original_payloads)
    finally:
        PAYLOADS_PATH.write_bytes(original_payload_bytes)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
