#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import subprocess
import tempfile

import pytest

PROJECT = Path('/home/user/audit_deadlocks')
OUTPUT = Path('/home/user/deadlocked_txs.txt')


def test_01_deadlocked_txs_output():
    assert OUTPUT.exists(), f'The output file {OUTPUT} does not exist. Did you run the program and write the output?'
    assert OUTPUT.is_file(), f'{OUTPUT} is not a file.'

    expected_lines = ['4', '5', '6', '10']
    actual_content = OUTPUT.read_text().strip()
    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f'The content of {OUTPUT} does not match the expected paginated deadlocked transaction IDs.\n'
        f'Expected: {expected_lines}\nActual: {actual_lines}'
    )


def is_elf_executable(path):
    try:
        return path.is_file() and os.access(path, os.X_OK) and path.open('rb').read(4) == b'\x7fELF'
    except OSError:
        return False


def choose_name(names):
    for name in names:
        if name.replace('-', '_') == 'audit_deadlocks':
            return name
    assert len(names) == 1, f'Could not identify the audit_deadlocks binary among: {names}'
    return names[0]


@pytest.fixture(scope='session')
def compiled_binary():
    assert PROJECT.exists(), f'{PROJECT} does not exist'

    if PROJECT.is_dir() and (PROJECT / 'Cargo.toml').is_file():
        rust_sources = list(PROJECT.rglob('*.rs'))
        assert rust_sources, 'The Cargo project contains no Rust source files'

        meta_run = subprocess.run(
            ['cargo', 'metadata', '--no-deps', '--format-version', '1'],
            cwd=PROJECT, text=True, capture_output=True, timeout=60
        )
        assert meta_run.returncode == 0, f'cargo metadata failed:\n{meta_run.stdout}\n{meta_run.stderr}'
        metadata = json.loads(meta_run.stdout)
        names = []
        for package in metadata['packages']:
            for target in package['targets']:
                if 'bin' in target.get('kind', []):
                    names.append(target['name'])
        names = sorted(set(names))
        assert names, 'The Rust project defines no binary target'
        name = choose_name(names)
        target_dir = Path(metadata['target_directory'])

        expected_existing = [target_dir / 'debug' / name, target_dir / 'release' / name]
        root_elfs = [p for p in PROJECT.iterdir() if is_elf_executable(p)]
        assert any(is_elf_executable(p) for p in expected_existing) or root_elfs, (
            'No precompiled Rust executable was found; the instruction requires the program to be compiled'
        )

        build = subprocess.run(
            ['cargo', 'build', '--release', '--bin', name],
            cwd=PROJECT, text=True, capture_output=True, timeout=180
        )
        assert build.returncode == 0, f'Rust project does not compile:\n{build.stdout}\n{build.stderr}'
        binary = target_dir / 'release' / name
        assert is_elf_executable(binary), f'Compiled binary was not produced at {binary}'
        return binary, PROJECT

    assert PROJECT.is_dir(), f'{PROJECT} must be a Rust project or standalone Rust program directory'
    sources = list(PROJECT.rglob('*.rs'))
    assert sources, f'No Rust source file exists under {PROJECT}'
    source = next((p for p in sources if p.name == 'main.rs'), sources[0] if len(sources) == 1 else None)
    assert source is not None, 'Could not identify the standalone Rust entry point'
    existing_elfs = [p for p in PROJECT.rglob('*') if is_elf_executable(p)]
    assert existing_elfs, 'No precompiled Rust executable was found'

    binary = Path('/tmp/audit_deadlocks_submission')
    build = subprocess.run(
        ['rustc', '--edition=2021', str(source), '-O', '-o', str(binary)],
        cwd=PROJECT, text=True, capture_output=True, timeout=180
    )
    assert build.returncode == 0, f'Standalone Rust program does not compile:\n{build.stdout}\n{build.stderr}'
    assert is_elf_executable(binary)
    return binary, PROJECT


def expected_deadlocks(edges, limit, offset):
    graph = {}
    nodes = set()
    for source, target in edges:
        graph.setdefault(source, []).append(target)
        nodes.add(source)
        nodes.add(target)

    cyclic = []
    for start in nodes:
        stack = list(graph.get(start, []))
        seen = set()
        in_cycle = False
        while stack:
            node = stack.pop()
            if node == start:
                in_cycle = True
                break
            if node in seen:
                continue
            seen.add(node)
            stack.extend(graph.get(node, []))
        if in_cycle:
            cyclic.append(start)

    cyclic.sort()
    return cyclic[offset:offset + limit]


def run_case(binary, cwd, edges, limit, offset):
    with tempfile.NamedTemporaryFile('w', suffix='.csv', delete=False) as csv_file:
        for source, target in edges:
            csv_file.write(f'{source},{target}\n')
        csv_path = csv_file.name

    try:
        OUTPUT.write_text('stale-output\n')
        result = subprocess.run(
            [str(binary), csv_path, str(limit), str(offset)],
            cwd=cwd, text=True, capture_output=True, timeout=15
        )
        assert result.returncode == 0, f'Program failed:\nstdout: {result.stdout}\nstderr: {result.stderr}'
        assert OUTPUT.is_file(), f'Program did not write {OUTPUT}'
        actual = [line.strip() for line in OUTPUT.read_text().splitlines() if line.strip()]
        expected = [str(value) for value in expected_deadlocks(edges, limit, offset)]
        assert actual == expected, f'Expected {expected}, got {actual}'
    finally:
        os.unlink(csv_path)


def test_02_binary_interface_and_general_graph_analysis(compiled_binary):
    binary, cwd = compiled_binary

    with tempfile.NamedTemporaryFile('w', suffix='.csv', delete=False) as csv_file:
        csv_file.write('1,1\n')
        csv_path = csv_file.name
    try:
        bad_argument_lists = [
            [csv_path],
            [csv_path, '2'],
            [csv_path, '2', '0', 'extra'],
        ]
        for arguments in bad_argument_lists:
            OUTPUT.unlink(missing_ok=True)
            subprocess.run([str(binary), *arguments], cwd=cwd, capture_output=True, timeout=10)
            assert not OUTPUT.exists(), f'Program accepted an invalid positional argument count: {arguments}'
    finally:
        os.unlink(csv_path)

    cases = [
        (
            [(100, 101), (101, 100), (5, 5), (20, 21), (21, 22), (22, 21),
             (30, 31), (200, 201), (201, 202), (202, 200), (400, 100)],
            3, 2
        ),
        (
            [(9, 10), (10, 11), (11, 12), (12, 10), (50, 51), (51, 50),
             (1, 2), (2, 3), (70, 70), (80, 50)],
            20, 0
        ),
        (
            [(3, 4), (4, 3), (8, 9), (9, 8), (12, 13), (13, 14), (14, 12),
             (1, 3), (20, 21)],
            2, 3
        ),
    ]
    for edges, limit, offset in cases:
        run_case(binary, cwd, edges, limit, offset)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
