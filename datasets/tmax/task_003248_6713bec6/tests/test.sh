#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import resource
import secrets
import shutil
import subprocess
from pathlib import Path

SOURCE = Path('/home/user/analyze_config.cpp')
EXECUTABLE = Path('/home/user/analyze_config')
CSV = Path('/home/user/config_stream.csv')
OUTPUT = Path('/home/user/closest_server.txt')
REBUILT = Path('/tmp/analyze_config_rebuilt')


def test_cpp_source_exists():
    assert SOURCE.exists(), f'Source file {SOURCE} is missing.'
    assert SOURCE.is_file(), f'Path {SOURCE} is not a file.'


def test_executable_exists():
    assert EXECUTABLE.exists(), f'Executable {EXECUTABLE} is missing.'
    assert EXECUTABLE.is_file(), f'Path {EXECUTABLE} is not a file.'
    assert os.access(EXECUTABLE, os.X_OK), f'File {EXECUTABLE} is not executable.'
    with EXECUTABLE.open('rb') as f:
        assert f.read(4) == b'\x7fELF', 'analyze_config must be a compiled executable.'


def limited_memory():
    limit = 96 * 1024 * 1024
    resource.setrlimit(resource.RLIMIT_AS, (limit, limit))


def run_program(program, memory_limited=False, timeout=40):
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        [str(program)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        preexec_fn=limited_memory if memory_limited else None,
    )
    assert result.returncode == 0, (
        f'{program} exited with {result.returncode}. stderr: {result.stderr[-2000:]}'
    )
    assert OUTPUT.exists(), f'Output file {OUTPUT} is missing after running {program}.'
    assert OUTPUT.is_file(), f'Path {OUTPUT} is not a file.'
    return OUTPUT.read_text().strip()


def expected_result(profiles):
    target = profiles['server_001']
    best_id = None
    best_score = -1.0
    for server_id, items in profiles.items():
        if server_id == 'server_001':
            continue
        union = target | items
        score = len(target & items) / len(union) if union else 0.0
        if score > best_score or (score == best_score and server_id < best_id):
            best_id = server_id
            best_score = score
    return f'{best_id},{best_score:.4f}'


def write_small_random_case():
    token = secrets.token_hex(5)
    winner_a = f'candidate_a_{token}'
    winner_b = f'candidate_b_{token}'
    target = {(f'K{i}', f'V{secrets.randbelow(1000000)}') for i in range(13)}
    profiles = {
        'server_001': target,
        winner_b: set(target),
        winner_a: set(target),
        f'other_{token}': set(list(target)[:6]) | {('EXTRA', 'different')},
    }
    rows = []
    for server_id, items in profiles.items():
        for key, value in items:
            rows.append(f'1700000000,{server_id},{key},{value}\n')
    # Distractor rows must not influence the target timestamp result.
    rows.extend([
        f'1699999999,{winner_a},BAD,VALUE\n',
        f'1700000001,server_001,BAD,VALUE\n',
        f'1700000001,distractor_{token},K0,V0\n',
    ])
    # Duplicate target rows must still behave as set items.
    key, value = next(iter(target))
    rows.append(f'1700000000,server_001,{key},{value}\n')
    CSV.write_text(''.join(rows))
    return expected_result(profiles)


def write_streaming_stress_case():
    token = secrets.token_hex(5)
    better = f'best_{token}'
    worse = f'other_{token}'
    target = {(f'KEY_{i:02d}', f'VALUE_{i:02d}') for i in range(12)}
    target_list = sorted(target)
    profiles = {
        'server_001': target,
        better: set(target_list[:11]) | {('EXTRA', 'A')},
        worse: set(target_list[:8]) | {('EXTRA', 'B')},
    }
    with CSV.open('w') as f:
        # Over 100 MB of irrelevant timestamps. A conforming implementation can
        # stream past these rows while retaining only the small target snapshot.
        for i in range(2_600_000):
            f.write(f'1699999999,noise_{i % 1000:03d},IGNORED_KEY,IGNORED_VALUE\n')
        for server_id, items in profiles.items():
            for key, value in items:
                f.write(f'1700000000,{server_id},{key},{value}\n')
    return expected_result(profiles)


def test_program_behavior_and_output():
    original_csv = CSV.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    try:
        compile_result = subprocess.run(
            ['g++', '-std=c++17', '-O2', str(SOURCE), '-o', str(REBUILT)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert compile_result.returncode == 0, (
            'analyze_config.cpp does not compile: ' + compile_result.stderr[-3000:]
        )

        # Preserve the original verifier's exact assertion, but only after
        # actually executing the submitted artifact on the supplied input.
        actual = run_program(EXECUTABLE)
        expected = 'server_077,0.8182'
        assert actual == expected, (
            f"Output file content is incorrect. Expected '{expected}', got '{actual}'."
        )

        # Exercise both the submitted executable and a fresh build of its source
        # on an unpredictable snapshot, including timestamp filtering and ties.
        expected = write_small_random_case()
        assert run_program(EXECUTABLE) == expected
        assert run_program(REBUILT) == expected

        # Enforce sequential processing with bounded memory on a large file whose
        # target timestamp contains only a few rows.
        expected = write_streaming_stress_case()
        assert run_program(EXECUTABLE, memory_limited=True) == expected
        assert run_program(REBUILT, memory_limited=True) == expected
    finally:
        CSV.write_bytes(original_csv)
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)


def test_output_file_contents():
    # The behavioral test restores the agent's original final output.
    assert OUTPUT.exists(), f'Output file {OUTPUT} is missing.'
    assert OUTPUT.is_file(), f'Path {OUTPUT} is not a file.'
    content = OUTPUT.read_text().strip()
    expected = 'server_077,0.8182'
    assert content == expected, f"Output file content is incorrect. Expected '{expected}', got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
