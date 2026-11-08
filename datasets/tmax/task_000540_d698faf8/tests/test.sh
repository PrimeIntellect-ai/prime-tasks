#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import datetime
import os
import pathlib
import shutil
import subprocess
import uuid

import pytest

SOURCE = pathlib.Path('/home/user/dataset_organizer.cpp')
CONFIG = pathlib.Path('/home/user/pipeline.conf')
BINARY = pathlib.Path('/tmp/dataset_organizer_verified')
ORIGINAL_EXPECTED = None


def parse_config(path):
    cfg = configparser.ConfigParser()
    with open(path, 'r', encoding='utf-8') as f:
        cfg.read_file(f)
    return {
        'input_dir': pathlib.Path(cfg['Input']['Directory']),
        'extension': cfg['Input']['Extension'],
        'max_year': int(cfg['Input']['MaxYear']),
        'source_encoding': cfg['Input']['OriginalEncoding'],
        'output_dir': pathlib.Path(cfg['Output']['Directory']),
        'prefix': cfg['Output']['Prefix'],
        'lines_per_chunk': int(cfg['Output']['LinesPerChunk']),
        'target_encoding': cfg['Output']['TargetEncoding'],
    }


def derive_expected(config_path):
    settings = parse_config(config_path)
    selected = []
    for path in settings['input_dir'].iterdir():
        if not path.is_file() or not path.name.endswith(settings['extension']):
            continue
        if datetime.datetime.fromtimestamp(path.stat().st_mtime).year <= settings['max_year']:
            selected.append(path)
    selected.sort(key=lambda p: p.name)

    merged_lines = []
    for path in selected:
        text = path.read_bytes().decode(settings['source_encoding'])
        merged_lines.extend(text.splitlines(keepends=True))

    expected = {}
    size = settings['lines_per_chunk']
    for start in range(0, len(merged_lines), size):
        index = start // size + 1
        name = f"{settings['prefix']}{index:03d}.txt"
        expected[name] = ''.join(merged_lines[start:start + size]).encode(settings['target_encoding'])
    return settings, expected


def reset_directory(path):
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def run_program(timeout=15):
    result = subprocess.run(
        [str(BINARY)], cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout
    )
    assert result.returncode == 0, (
        f'Program exited with {result.returncode}.\n'
        f'stdout: {result.stdout.decode(errors="replace")}\n'
        f'stderr: {result.stderr.decode(errors="replace")}'
    )


def assert_exact_output(settings, expected):
    output_dir = settings['output_dir']
    assert output_dir.is_dir(), f'Missing output directory: {output_dir}'
    actual_names = sorted(
        p.name for p in output_dir.iterdir()
        if p.name.startswith(settings['prefix'])
    )
    assert actual_names == sorted(expected), (
        f'Expected chunk filenames {sorted(expected)}, got {actual_names}'
    )
    for name, expected_bytes in expected.items():
        path = output_dir / name
        assert path.is_file(), f'{path} is not a regular file'
        actual_bytes = path.read_bytes()
        assert actual_bytes == expected_bytes, f'Incorrect contents in {name}'
        actual_bytes.decode('utf-8')


@pytest.fixture(scope='session', autouse=True)
def compile_execute_and_exercise_program(tmp_path_factory):
    global ORIGINAL_EXPECTED

    assert SOURCE.is_file(), 'Required /home/user/dataset_organizer.cpp is missing'
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', str(SOURCE), '-o', str(BINARY)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert compile_result.returncode == 0, (
        'dataset_organizer.cpp did not compile.\n'
        + compile_result.stderr.decode(errors='replace')
    )
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), 'Compiled artifact is not executable'

    original_config = CONFIG.read_bytes()
    original_settings, ORIGINAL_EXPECTED = derive_expected(CONFIG)

    probe_root = tmp_path_factory.mktemp('organizer_probe')
    probe_input = probe_root / 'input'
    probe_output = probe_root / 'output'
    probe_input.mkdir()
    probe_output.mkdir()
    token = uuid.uuid4().hex

    files = {
        'zeta.bin': f'zeta-{token}-café\nzeta-second-{token}\n',
        'alpha.bin': f'alpha-{token}-façade\nalpha-second-{token}\nalpha-third-{token}\n',
        'future.bin': f'must-not-appear-{token}\n',
        'wrong.txt': f'wrong-extension-{token}\n',
    }
    for name, text in files.items():
        (probe_input / name).write_bytes(text.encode('windows-1252'))

    old_time = datetime.datetime(2020, 6, 1, 12, 0).timestamp()
    future_time = datetime.datetime(2022, 6, 1, 12, 0).timestamp()
    for name in ('zeta.bin', 'alpha.bin', 'wrong.txt'):
        os.utime(probe_input / name, (old_time, old_time))
    os.utime(probe_input / 'future.bin', (future_time, future_time))

    probe_prefix = 'probe_' + token[:8] + '_'
    probe_config = f'''[Input]
Directory={probe_input}
Extension=.bin
MaxYear=2021
OriginalEncoding=WINDOWS-1252

[Output]
Directory={probe_output}
Prefix={probe_prefix}
LinesPerChunk=2
TargetEncoding=UTF-8
'''

    try:
        CONFIG.write_text(probe_config, encoding='utf-8')
        probe_settings, probe_expected = derive_expected(CONFIG)
        reset_directory(probe_output)
        run_program()
        assert_exact_output(probe_settings, probe_expected)
    finally:
        CONFIG.write_bytes(original_config)

    reset_directory(original_settings['output_dir'])
    run_program()
    assert_exact_output(original_settings, ORIGINAL_EXPECTED)
    yield


def test_processed_files_exist_and_count():
    processed_dir = '/home/user/processed_data'
    files = sorted(os.listdir(processed_dir))

    chunk_files = [f for f in files if f.startswith('dataset_chunk_')]

    assert len(chunk_files) == 3, f'Expected exactly 3 chunk files, found {len(chunk_files)}: {chunk_files}'
    assert chunk_files == [
        'dataset_chunk_001.txt',
        'dataset_chunk_002.txt',
        'dataset_chunk_003.txt',
    ]


def test_processed_files_content_and_encoding():
    processed_dir = '/home/user/processed_data'
    files = sorted([f for f in os.listdir(processed_dir) if f.startswith('dataset_chunk_')])

    assert len(files) == 3, 'Need exactly 3 chunk files to test contents.'

    all_lines = []

    for filename in files:
        filepath = os.path.join(processed_dir, filename)
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                lines = f.readlines()
        except UnicodeDecodeError:
            pytest.fail(f'File {filename} is not valid UTF-8.')

        assert len(lines) == 15, f'File {filename} should have exactly 15 lines, got {len(lines)}.'
        all_lines.extend(lines)

    assert len(all_lines) == 45, f'Expected 45 total lines, got {len(all_lines)}.'

    for i in range(20):
        assert 'café' in all_lines[i], f"Line {i+1} expected to contain 'café', but got: {all_lines[i]}"

    for i in range(20, 45):
        assert 'façade' in all_lines[i], f"Line {i+1} expected to contain 'façade', but got: {all_lines[i]}"


def test_original_output_matches_selected_source_files_exactly():
    settings, expected = derive_expected(CONFIG)
    assert expected == ORIGINAL_EXPECTED
    assert_exact_output(settings, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
