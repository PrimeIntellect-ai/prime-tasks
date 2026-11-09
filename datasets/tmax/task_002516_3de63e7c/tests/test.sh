#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import hashlib
import gzip
import tempfile

SOURCE = '/home/user/zsha256.c'
EXECUTABLE = '/home/user/zsha256'


def exercise_checksum_tool(executable):
    payloads = [
        b'',
        os.urandom(37),
        os.urandom(131071),
        b'not a fixture payload\x00with binary bytes\xff' + os.urandom(4096),
    ]

    with tempfile.TemporaryDirectory(prefix='zsha256-verifier-') as tmpdir:
        for index, payload in enumerate(payloads):
            test_file = os.path.join(tmpdir, f'random-{index}-{os.urandom(8).hex()}.gz')
            with gzip.open(test_file, 'wb') as stream:
                stream.write(payload)

            result = subprocess.run(
                [executable, test_file],
                capture_output=True,
                timeout=15,
            )
            assert result.returncode == 0, (
                f'{executable} failed on verifier-generated gzip input: '
                f'{result.stderr.decode(errors="replace")}'
            )
            expected = hashlib.sha256(payload).hexdigest().encode() + b'\n'
            assert result.stdout == expected, (
                f'{executable} produced {result.stdout!r}; expected {expected!r}'
            )


def test_c_program_exists():
    assert os.path.isfile(SOURCE), "C source code /home/user/zsha256.c is missing."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, 'rb') as stream:
        assert stream.read(4) == b'\x7fELF', f"Executable {EXECUTABLE} is not a compiled native binary."


def test_executable_behavior():
    test_file = '/home/user/repo/art1.gz'

    if not os.path.isfile(EXECUTABLE) or not os.path.isfile(test_file):
        return  # Handled by other tests

    result = subprocess.run([EXECUTABLE, test_file], capture_output=True, text=True)
    assert result.returncode == 0, "Executable failed to run on a valid .gz file."

    expected_hash = "72a2e412ddc2941198edcc549ed0f9ca22dd5c192d27464ce7ec017e4bb07c13"
    output = result.stdout.strip()
    assert output == expected_hash, f"Executable output '{output}' did not match expected hash '{expected_hash}'."


def test_executable_on_unpredictable_inputs():
    exercise_checksum_tool(EXECUTABLE)


def test_source_compiles_and_rebuilt_program_works():
    assert os.path.isfile(SOURCE), "C source code /home/user/zsha256.c is missing."
    with tempfile.TemporaryDirectory(prefix='zsha256-build-') as tmpdir:
        rebuilt = os.path.join(tmpdir, 'zsha256-rebuilt')
        result = subprocess.run(
            ['gcc', '-o', rebuilt, SOURCE, '-lz', '-lcrypto'],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f'C source failed to compile: {result.stderr}'
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
        exercise_checksum_tool(rebuilt)


def test_curated_directory_exists():
    assert os.path.isdir('/home/user/curated'), "Directory /home/user/curated is missing."


def test_curated_files_exist():
    expected_files = [
        "72a2e412ddc2941198edcc549ed0f9ca22dd5c192d27464ce7ec017e4bb07c13.gz",
        "c864a6eeb1821034bcff24976c66cf10cf54cd7da9c1851e2bc68b8a0dfbcda6.gz",
        "92520330ce9c2e0b503028fb4abef52bf482ab87019310d65ffc4fbcbb0b6c6b.gz",
        "manifest.txt"
    ]

    for filename in expected_files:
        path = os.path.join('/home/user/curated', filename)
        assert os.path.isfile(path), f"Expected file {path} is missing."


def test_manifest_content():
    manifest_path = '/home/user/curated/manifest.txt'
    assert os.path.isfile(manifest_path), "Manifest file is missing."

    expected_content = (
        "72a2e412ddc2941198edcc549ed0f9ca22dd5c192d27464ce7ec017e4bb07c13 art1.gz\n"
        "92520330ce9c2e0b503028fb4abef52bf482ab87019310d65ffc4fbcbb0b6c6b subdir/art3.gz\n"
        "c864a6eeb1821034bcff24976c66cf10cf54cd7da9c1851e2bc68b8a0dfbcda6 subdir/art2.gz\n"
    )

    with open(manifest_path, 'r') as stream:
        content = stream.read()

    assert content == expected_content, "Manifest file content does not match the expected sorted output."


def test_curated_gz_files_validity():
    expected_data = {
        "72a2e412ddc2941198edcc549ed0f9ca22dd5c192d27464ce7ec017e4bb07c13": b"artifact_one_data",
        "c864a6eeb1821034bcff24976c66cf10cf54cd7da9c1851e2bc68b8a0dfbcda6": b"artifact_two_data_v2",
        "92520330ce9c2e0b503028fb4abef52bf482ab87019310d65ffc4fbcbb0b6c6b": b"artifact_three_data_final"
    }

    for checksum, data in expected_data.items():
        path = f"/home/user/curated/{checksum}.gz"
        if os.path.isfile(path):
            with gzip.open(path, 'rb') as stream:
                content = stream.read()
            assert content == data, f"Uncompressed content of {path} does not match expected data."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
