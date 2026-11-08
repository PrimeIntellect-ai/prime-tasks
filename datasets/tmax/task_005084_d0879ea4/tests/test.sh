#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

PROJECT = Path('/home/user/msg_gateway')
LIBDIR = Path('/app/libmsgparse-1.2.0')
LIBRARY = LIBDIR / 'libmsgparse.so'
BINARY = PROJECT / 'target/debug/msg_gateway'


def run(cmd, **kwargs):
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('timeout', 30)
    return subprocess.run(cmd, **kwargs)


def assert_error_result(result, description):
    assert result.returncode == 1, (
        f'{description}: expected exit 1, got {result.returncode}; '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert result.stdout.strip() or result.stderr.strip(), (
        f'{description}: malformed input produced no error output'
    )


def test_final_state():
    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = str(LIBDIR)

    # Remove prior build products so make must actually produce the shared library.
    for pattern in ('*.o', '*.a', '*.so'):
        for path in LIBDIR.glob(pattern):
            path.unlink()

    make_res = run(['make'], cwd=LIBDIR, env=env, text=True)
    assert make_res.returncode == 0, (
        f'make failed:\nstdout:\n{make_res.stdout}\nstderr:\n{make_res.stderr}'
    )
    assert LIBRARY.is_file(), 'make did not produce libmsgparse.so'

    elf_res = run(['readelf', '-h', str(LIBRARY)], text=True)
    assert elf_res.returncode == 0, f'libmsgparse.so is not a readable ELF file: {elf_res.stderr}'
    assert re.search(r'^\s*Type:\s+DYN\b', elf_res.stdout, re.MULTILINE), (
        'libmsgparse.so is not an ELF shared object'
    )
    exports = run(['nm', '-D', str(LIBRARY)], text=True)
    assert exports.returncode == 0, f'Could not inspect libmsgparse.so: {exports.stderr}'
    assert re.search(r'\bT\s+parse_msg(?:$|@)', exports.stdout, re.MULTILINE), (
        'libmsgparse.so does not export parse_msg'
    )

    clean_res = run(
        ['cargo', 'clean', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        env=env,
        text=True,
    )
    assert clean_res.returncode == 0, f'cargo clean failed: {clean_res.stderr}'

    build_res = run(
        ['cargo', 'build', '--manifest-path', str(PROJECT / 'Cargo.toml')],
        env=env,
        text=True,
    )
    assert build_res.returncode == 0, (
        f'Cargo build failed:\nstdout:\n{build_res.stdout}\nstderr:\n{build_res.stderr}'
    )
    assert BINARY.is_file(), 'Compiled binary not found at expected path.'

    dynamic = run(['readelf', '-d', str(BINARY)], text=True)
    assert dynamic.returncode == 0, f'Could not inspect compiled binary: {dynamic.stderr}'
    assert re.search(r'NEEDED.*\[libmsgparse\.so\]', dynamic.stdout), (
        'Compiled binary is not dynamically linked to libmsgparse.so'
    )
    symbols = run(['nm', '-D', str(BINARY)], text=True)
    assert symbols.returncode == 0, f'Could not inspect compiled binary symbols: {symbols.stderr}'
    assert re.search(r'\bU\s+parse_msg(?:$|@)', symbols.stdout, re.MULTILINE), (
        'Compiled binary does not import parse_msg through the FFI'
    )

    # Retain the original corpus assertions and additionally require diagnostics.
    clean_corpus = glob.glob('/app/corpora/clean/*')
    evil_corpus = glob.glob('/app/corpora/evil/*')
    assert len(clean_corpus) > 0, 'No clean corpus files found.'
    assert len(evil_corpus) > 0, 'No evil corpus files found.'

    clean_failed = []
    for filename in clean_corpus:
        result = run([str(BINARY), filename], env=env)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(filename))

    evil_failed = []
    for filename in evil_corpus:
        result = run([str(BINARY), filename], env=env)
        if result.returncode != 1 or not (result.stdout.strip() or result.stderr.strip()):
            evil_failed.append(os.path.basename(filename))

    messages = []
    if clean_failed:
        messages.append(
            f'{len(clean_failed)} of {len(clean_corpus)} clean modified '
            f'(expected exit 0): {", ".join(clean_failed)}'
        )
    if evil_failed:
        messages.append(
            f'{len(evil_failed)} of {len(evil_corpus)} evil inputs were not gracefully '
            f'rejected with exit 1 and error output: {", ".join(evil_failed)}'
        )
    assert not clean_failed and not evil_failed, ' | '.join(messages)

    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    with tempfile.TemporaryDirectory(prefix='msg_gateway_checks_') as temp_dir:
        temp = Path(temp_dir)
        valid_paths = []
        invalid_paths = []

        # Generate valid inputs with boundary lengths and unpredictable contents/names.
        for payload_len in (0, 1, 2, 7, 31, 255, 256, 1024, 4096, 65535):
            msg_type = rng.randrange(256)
            payload = os.urandom(payload_len)
            data = bytes([msg_type]) + payload_len.to_bytes(2, 'big') + payload
            path = temp / f'valid_{rng.getrandbits(64):016x}.dat'
            path.write_bytes(data)
            valid_paths.append(path)

        # Inputs shorter than the three-byte header.
        for data in (b'', b'\x01', b'\x01\x00'):
            path = temp / f'truncated_header_{rng.getrandbits(64):016x}.dat'
            path.write_bytes(data)
            invalid_paths.append(path)

        # Derive malformed cases by making actual data shorter or longer than its header.
        for declared in (0, 1, 2, 17, 255, 256, 4096, 65535):
            actual_lengths = {declared + 1}
            if declared > 0:
                actual_lengths.add(declared - 1)
            else:
                actual_lengths.add(2)
            for actual in actual_lengths:
                data = bytes([rng.randrange(256)]) + declared.to_bytes(2, 'big') + os.urandom(actual)
                path = temp / f'invalid_{rng.getrandbits(64):016x}.dat'
                path.write_bytes(data)
                invalid_paths.append(path)

        for path in valid_paths:
            result = run([str(BINARY), str(path)], env=env)
            assert result.returncode == 0, (
                f'Generated valid input of {path.stat().st_size} bytes failed with '
                f'{result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}'
            )

        for path in invalid_paths:
            assert_error_result(run([str(BINARY), str(path)], env=env), str(path))

        # Replace the library temporarily with a probe. Valid inputs must reach parse_msg,
        # while malformed inputs must be rejected before crossing the FFI boundary.
        probe_source = temp / 'probe.c'
        probe_library = temp / 'libmsgparse.so'
        backup_library = temp / 'original_libmsgparse.so'
        probe_source.write_text(
            '#include <stddef.h>\n'
            '#include <unistd.h>\n'
            'void parse_msg(const unsigned char *data, size_t len) {\n'
            '    (void)data; (void)len; _exit(73);\n'
            '}\n'
        )
        probe_build = run(
            ['gcc', '-shared', '-fPIC', str(probe_source), '-o', str(probe_library)],
            text=True,
        )
        assert probe_build.returncode == 0, f'Failed to build FFI probe: {probe_build.stderr}'

        shutil.copy2(LIBRARY, backup_library)
        original_mode = stat.S_IMODE(LIBRARY.stat().st_mode)
        try:
            shutil.copy2(probe_library, LIBRARY)
            os.chmod(LIBRARY, original_mode)

            for path in valid_paths[:4]:
                result = run([str(BINARY), str(path)], env=env)
                assert result.returncode == 73, (
                    'A generated valid input did not call the C parse_msg function; '
                    f'got exit {result.returncode}'
                )

            for path in invalid_paths:
                assert_error_result(
                    run([str(BINARY), str(path)], env=env),
                    f'{path} with FFI probe',
                )
        finally:
            shutil.copy2(backup_library, LIBRARY)
            os.chmod(LIBRARY, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
