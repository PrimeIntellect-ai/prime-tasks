#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_pipeline.py
import os
import re
import secrets
import shutil
import stat
import string
import subprocess
import tempfile
from pathlib import Path

import pytest

HOME = Path('/home/user')


def run(cmd, timeout=20, cwd=None):
    result = subprocess.run(
        cmd, cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout
    )
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def random_id():
    alphabet = string.ascii_uppercase + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(5))


def test_directories_created():
    expected_dirs = [
        '/home/user/accepted',
        '/home/user/rejected',
        '/home/user/output',
        '/home/user/logs'
    ]
    for d in expected_dirs:
        assert os.path.isdir(d), f"Directory {d} was not created."


def test_accepted_files():
    accepted_dir = '/home/user/accepted'
    expected_files = {'data1.csv', 'data3.csv'}

    assert os.path.isdir(accepted_dir), f"{accepted_dir} does not exist."
    actual_files = set(os.listdir(accepted_dir))

    for f in expected_files:
        assert f in actual_files, f"Expected {f} to be in {accepted_dir}, but it was not."


def test_rejected_files():
    rejected_dir = '/home/user/rejected'
    expected_files = {'data2.csv', 'data4.csv'}

    assert os.path.isdir(rejected_dir), f"{rejected_dir} does not exist."
    actual_files = set(os.listdir(rejected_dir))

    for f in expected_files:
        assert f in actual_files, f"Expected {f} to be in {rejected_dir}, but it was not."


def test_consolidated_csv_content():
    output_file = '/home/user/output/consolidated.csv'
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    expected_lines = [
        "A1B2C,User logged in successfully.",
        "P0O9I,Query execution took 45ms.",
        "Q1W2E,Database connection lost! Retry in 5s...",
        "X9Y8Z,Failed to load module auth."
    ]

    with open(output_file, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {output_file} do not match expected output. "
        f"Expected:\n{expected_lines}\nGot:\n{actual_lines}"
    )


def test_pipeline_log_content():
    log_file = '/home/user/logs/pipeline.log'
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, 'r') as f:
        content = f.read()

    assert "START: Validation" in content, f"'START: Validation' missing from {log_file}"
    assert "START: Cleaning" in content, f"'START: Cleaning' missing from {log_file}"
    assert "END: Pipeline complete" in content, f"'END: Pipeline complete' missing from {log_file}"

    idx1 = content.find("START: Validation")
    idx2 = content.find("START: Cleaning")
    idx3 = content.find("END: Pipeline complete")

    assert idx1 < idx2 < idx3, "Log messages are not in the correct order."


def test_required_artifacts_exist_and_sources_compile(tmp_path):
    for source in (HOME / 'validator.cpp', HOME / 'cleaner.cpp'):
        assert source.is_file(), f"Missing C++ source file: {source}"
        assert not source.is_symlink(), f"C++ source must be a regular file: {source}"
        assert source.stat().st_size > 0, f"C++ source is empty: {source}"

    for binary in (HOME / 'validator', HOME / 'cleaner'):
        assert binary.is_file(), f"Missing compiled program: {binary}"
        assert os.access(binary, os.X_OK), f"Program is not executable: {binary}"
        with binary.open('rb') as f:
            assert f.read(4) == b'\x7fELF', f"Program is not a compiled ELF binary: {binary}"

    pipeline = HOME / 'pipeline.sh'
    assert pipeline.is_file(), "Missing /home/user/pipeline.sh"
    assert os.access(pipeline, os.X_OK), "/home/user/pipeline.sh is not executable"

    rebuilt_validator = tmp_path / 'validator-rebuilt'
    rebuilt_cleaner = tmp_path / 'cleaner-rebuilt'
    run(['g++', '-std=c++17', str(HOME / 'validator.cpp'), '-o', str(rebuilt_validator)])
    run(['g++', '-std=c++17', str(HOME / 'cleaner.cpp'), '-o', str(rebuilt_cleaner)])
    assert rebuilt_validator.exists() and os.access(rebuilt_validator, os.X_OK)
    assert rebuilt_cleaner.exists() and os.access(rebuilt_cleaner, os.X_OK)


def exercise_validator(program, root):
    input_dir = root / 'input'
    accepted = root / 'accepted'
    rejected = root / 'rejected'
    input_dir.mkdir()
    accepted.mkdir()
    rejected.mkdir()

    names = [secrets.token_hex(6) + '.csv' for _ in range(5)]
    valid1 = f"{random_id()},2026-01-09,INFO,ordinary message\n"
    valid2 = (
        f"{random_id()},1999-12-31,WARN,<b>tagged</b> message\n"
        f"{random_id()},2000-02-29,ERROR,second row\n"
    )
    invalid_id = "A-123,2025-11-30,INFO,bad id\n"
    invalid_date = f"{random_id()},2025-1-30,WARN,bad date length\n"
    invalid_level = (
        f"{random_id()},2025-11-30,INFO,first valid row\n"
        f"{random_id()},2025-11-30,DEBUG,bad level\n"
    )
    payloads = dict(zip(names, [valid1, valid2, invalid_id, invalid_date, invalid_level]))
    for name, content in payloads.items():
        (input_dir / name).write_text(content)
    (input_dir / (secrets.token_hex(5) + '.txt')).write_text('not a csv')

    run([str(program), str(input_dir), str(accepted), str(rejected)])

    assert {p.name for p in accepted.iterdir()} == set(names[:2])
    assert {p.name for p in rejected.iterdir()} == set(names[2:])
    assert not any(input_dir.glob('*.csv')), "Validator did not move all CSV files"
    for name in names[:2]:
        assert (accepted / name).read_text() == payloads[name]
    for name in names[2:]:
        assert (rejected / name).read_text() == payloads[name]


def exercise_cleaner(program, root):
    accepted = root / 'accepted'
    accepted.mkdir()
    output = root / 'result.csv'

    ids = {random_id() for _ in range(4)}
    while len(ids) < 4:
        ids.add(random_id())
    ids = list(ids)
    rows = [
        (ids[0], '<b>Alpha</b> and <span class="x">Beta</span>.'),
        (ids[1], 'Plain message.'),
        (ids[2], '<one></one>Tail'),
        (ids[3], 'Before <tag attr="v">middle</tag> after.'),
    ]
    (accepted / (secrets.token_hex(6) + '.csv')).write_text(
        ''.join(f"{rid},2026-08-21,INFO,{message}\n" for rid, message in rows[:2])
    )
    (accepted / (secrets.token_hex(6) + '.csv')).write_text(
        ''.join(f"{rid},2026-08-22,ERROR,{message}\n" for rid, message in rows[2:])
    )
    (accepted / 'ignored.txt').write_text('ignore me')

    run([str(program), str(accepted), str(output)])
    expected = sorted(
        f"{rid},{re.sub(r'<[^>]*>', '', message)}" for rid, message in rows
    )
    actual = output.read_text().splitlines()
    assert actual == expected, f"Cleaner output mismatch: expected {expected}, got {actual}"


def test_submitted_and_source_built_programs_work(tmp_path):
    exercise_validator(HOME / 'validator', tmp_path / 'submitted-validator')
    exercise_cleaner(HOME / 'cleaner', tmp_path / 'submitted-cleaner')

    rebuilt_validator = tmp_path / 'validator-rebuilt'
    rebuilt_cleaner = tmp_path / 'cleaner-rebuilt'
    run(['g++', '-std=c++17', str(HOME / 'validator.cpp'), '-o', str(rebuilt_validator)])
    run(['g++', '-std=c++17', str(HOME / 'cleaner.cpp'), '-o', str(rebuilt_cleaner)])
    exercise_validator(rebuilt_validator, tmp_path / 'rebuilt-validator-case')
    exercise_cleaner(rebuilt_cleaner, tmp_path / 'rebuilt-cleaner-case')


def test_pipeline_executes_both_programs_on_fresh_dynamic_input(tmp_path):
    for name in ('input', 'accepted', 'rejected', 'output', 'logs'):
        path = HOME / name
        if path.exists():
            shutil.rmtree(path)
    (HOME / 'input').mkdir()

    valid_ids = [random_id(), random_id(), random_id()]
    while len(set(valid_ids)) != 3:
        valid_ids = [random_id(), random_id(), random_id()]

    valid_files = {
        secrets.token_hex(6) + '.csv': (
            f"{valid_ids[0]},2026-09-01,INFO,<b>First</b> message.\n"
            f"{valid_ids[1]},2026-09-02,WARN,Second <i>clean</i> message.\n"
        ),
        secrets.token_hex(6) + '.csv':
            f"{valid_ids[2]},2026-09-03,ERROR,Third message.\n",
    }
    rejected_files = {
        secrets.token_hex(6) + '.csv':
            f"BAD!,2026-09-04,INFO,invalid identifier\n",
        secrets.token_hex(6) + '.csv':
            f"{random_id()},2026-09-05,TRACE,invalid level\n",
    }
    for name, data in {**valid_files, **rejected_files}.items():
        (HOME / 'input' / name).write_text(data)

    validator = HOME / 'validator'
    cleaner = HOME / 'cleaner'
    validator_real = HOME / '.validator.verifier-real'
    cleaner_real = HOME / '.cleaner.verifier-real'
    marker = tmp_path / 'calls.log'
    for backup in (validator_real, cleaner_real):
        if backup.exists():
            backup.unlink()

    os.replace(validator, validator_real)
    os.replace(cleaner, cleaner_real)
    try:
        validator.write_text(
            '#!/bin/bash\n'
            f"echo validator >> {marker}\n"
            f'exec {validator_real} "$@"\n'
        )
        cleaner.write_text(
            '#!/bin/bash\n'
            f"echo cleaner >> {marker}\n"
            f'exec {cleaner_real} "$@"\n'
        )
        validator.chmod(0o755)
        cleaner.chmod(0o755)

        run([str(HOME / 'pipeline.sh')], timeout=30, cwd=str(HOME))
    finally:
        if validator.exists():
            validator.unlink()
        if cleaner.exists():
            cleaner.unlink()
        if validator_real.exists():
            os.replace(validator_real, validator)
        if cleaner_real.exists():
            os.replace(cleaner_real, cleaner)

    assert marker.is_file(), "Pipeline did not invoke the required programs"
    calls = marker.read_text().splitlines()
    assert calls.count('validator') == 1, "Pipeline must invoke validator once"
    assert calls.count('cleaner') == 1, "Pipeline must invoke cleaner once"
    assert calls.index('validator') < calls.index('cleaner'), "Cleaner ran before validator"

    for directory in ('accepted', 'rejected', 'output', 'logs'):
        assert (HOME / directory).is_dir(), f"Pipeline did not create {directory}"
    assert {p.name for p in (HOME / 'accepted').iterdir()} == set(valid_files)
    assert {p.name for p in (HOME / 'rejected').iterdir()} == set(rejected_files)

    expected_messages = {
        valid_ids[0]: 'First message.',
        valid_ids[1]: 'Second clean message.',
        valid_ids[2]: 'Third message.',
    }
    expected_output = [f"{rid},{expected_messages[rid]}" for rid in sorted(expected_messages)]
    output_file = HOME / 'output' / 'consolidated.csv'
    assert output_file.is_file()
    assert output_file.read_text().splitlines() == expected_output

    log_file = HOME / 'logs' / 'pipeline.log'
    assert log_file.is_file()
    log = log_file.read_text()
    first = log.find('START: Validation')
    second = log.find('START: Cleaning')
    third = log.find('END: Pipeline complete')
    assert first >= 0 and second >= 0 and third >= 0
    assert first < second < third
TEST_EOF

if python3 -m pytest /tmp/test_pipeline.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
