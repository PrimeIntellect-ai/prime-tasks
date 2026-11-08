#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import re
import subprocess
import tempfile


def djb2_32(s):
    h = 5381
    for c in s:
        h = ((h << 5) + h) + ord(c)
        h &= 0xFFFFFFFF
    return h


def djb2_64(s):
    h = 5381
    for c in s:
        h = ((h << 5) + h) + ord(c)
        h &= 0xFFFFFFFFFFFFFFFF
    return h


def get_normalized_strings(raw_file):
    with open(raw_file, 'r') as f:
        lines = f.read().splitlines()

    normalized = []
    for line in lines:
        match = re.search(r'"([^"]*)"', line)
        if match:
            text = match.group(1)
            text = text.lower()
            text = re.sub(r'[^a-z0-9 ]', '', text)
            normalized.append(text)
    return normalized


def test_final_sample_exists():
    assert os.path.isfile('/home/user/final_sample.txt'), "The file /home/user/final_sample.txt does not exist."


def test_final_sample_content():
    raw_file = '/home/user/raw_strings.txt'
    assert os.path.isfile(raw_file), "The file raw_strings.txt is missing."

    normalized_strings = get_normalized_strings(raw_file)

    # Deduplicate while preserving order of first appearance (though we will sort later)
    unique_strings = []
    seen = set()
    for s in normalized_strings:
        if s not in seen:
            seen.add(s)
            unique_strings.append(s)

    expected_32 = sorted([s for s in unique_strings if djb2_32(s) % 10 == 0])
    expected_64 = sorted([s for s in unique_strings if djb2_64(s) % 10 == 0])

    with open('/home/user/final_sample.txt', 'r') as f:
        actual = f.read().splitlines()

    assert actual == expected_32 or actual == expected_64, (
        f"The content of /home/user/final_sample.txt is incorrect.\n"
        f"Expected (64-bit hash): {expected_64}\n"
        f"Expected (32-bit hash): {expected_32}\n"
        f"Actual: {actual}"
    )


def test_c_source_and_executable_exist():
    assert os.path.isfile('/home/user/process_strings.c'), "The C source file /home/user/process_strings.c does not exist."
    assert os.path.isfile('/home/user/process_strings'), "The compiled executable /home/user/process_strings does not exist."
    assert os.access('/home/user/process_strings', os.X_OK), "The file /home/user/process_strings is not executable."


def expected_program_output(lines, bits):
    mask = (1 << bits) - 1
    seen_hashes = set()
    output = []
    for line in lines:
        match = re.search(r'"([^"]*)"', line)
        if not match:
            continue
        normalized = re.sub(r'[^a-z0-9 ]', '', match.group(1).lower())
        h = 5381
        for c in normalized:
            h = (((h << 5) + h) + ord(c)) & mask
        if h in seen_hashes:
            continue
        seen_hashes.add(h)
        if h % 10 == 0:
            output.append(normalized)
    return output


def find_collision_suffix_sampled_for_both_widths():
    # "ac " and "aab" have the same DJB2 hash. Find a shared suffix for
    # which that hash is sampled under both common unsigned widths.
    alphabet = '0123456789abcdefghijklmnopqrstuvwxyz'
    for length in range(1, 5):
        for chars in itertools.product(alphabet, repeat=length):
            suffix = ''.join(chars)
            left = 'ac ' + suffix
            right = 'aab' + suffix
            if djb2_32(left) == djb2_32(right) and djb2_64(left) == djb2_64(right):
                if djb2_32(left) % 10 == 0 and djb2_64(left) % 10 == 0:
                    return suffix
    raise AssertionError('Unable to construct DJB2 collision fixture')


def find_common_unsampled_string():
    for i in range(10000):
        value = f'not sampled {i}'
        if djb2_32(value) % 10 != 0 and djb2_64(value) % 10 != 0:
            return value
    raise AssertionError('Unable to construct unsampled fixture')


def test_program_compiles_and_processes_controlled_input():
    source = '/home/user/process_strings.c'
    installed_executable = '/home/user/process_strings'
    raw_file = '/home/user/raw_strings.txt'

    suffix = find_collision_suffix_sampled_for_both_widths()
    unsampled = find_common_unsampled_string()
    lines = [
        f'COLLISION_FIRST: "AC {suffix}"',
        f'COLLISION_SECOND: "AAB{suffix}"',
        f'DUPLICATE: "ac {suffix}!!!"',
        f'FILTERED: "{unsampled.upper()}...?"',
        'NO_QUOTES: this line must be ignored',
        'EXTRA_QUOTES: "First Value" and "Second Value"',
        'LONG_LINE: "' + ('Ab- ' * 225) + '"',
    ]
    fixture = ('\n'.join(lines) + '\n').encode()
    expected_32 = expected_program_output(lines, 32)
    expected_64 = expected_program_output(lines, 64)

    with open(raw_file, 'rb') as f:
        original_raw = f.read()

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt_executable = os.path.join(temp_dir, 'process_strings')
        compile_result = subprocess.run(
            ['gcc', '-o', rebuilt_executable, source],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            'The submitted C source does not compile with gcc:\n' + compile_result.stderr
        )

        try:
            for executable in (installed_executable, rebuilt_executable):
                with open(raw_file, 'wb') as f:
                    f.write(fixture)
                result = subprocess.run(
                    [executable],
                    cwd='/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
                assert result.returncode == 0, (
                    f'{executable} exited with status {result.returncode}.\n'
                    f'stderr: {result.stderr}'
                )
                actual = result.stdout.splitlines()
                assert actual == expected_32 or actual == expected_64, (
                    f'{executable} did not correctly normalize, hash-deduplicate, and sample '
                    f'the controlled input.\nExpected 32-bit: {expected_32}\n'
                    f'Expected 64-bit: {expected_64}\nActual: {actual}'
                )
        finally:
            with open(raw_file, 'wb') as f:
                f.write(original_raw)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
