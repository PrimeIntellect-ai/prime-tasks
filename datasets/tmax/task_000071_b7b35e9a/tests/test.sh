#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_artifacts.py
import os
import secrets
import stat
import struct
import subprocess
import tempfile
from pathlib import Path

ARTIFACTS_DIR = Path('/home/user/artifacts')
CORRUPT_LOG = Path('/home/user/corrupt.log')
SOURCE = Path('/home/user/process_artifacts.cpp')
PROCESSOR = Path('/home/user/processor')
MAGIC = 0xDEADC0DE


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


# Preserve the original final-state assertions.
def check_original_final_state():
    bad_txt_1 = ARTIFACTS_DIR / 'project_beta' / 'metrics.txt.tmp'
    bad_txt_2 = ARTIFACTS_DIR / 'project_beta' / 'metrics.bin.tmp.txt'
    assert not bad_txt_1.exists(), f'Expected {bad_txt_1} not to exist, but it does.'
    assert not bad_txt_2.exists(), f'Expected {bad_txt_2} not to exist, but it does.'

    assert CORRUPT_LOG.is_file(), f'{CORRUPT_LOG} does not exist.'
    expected_corrupt = [
        str(ARTIFACTS_DIR / 'project_gamma' / 'bad_magic.bin'),
        str(ARTIFACTS_DIR / 'project_gamma' / 'truncated.bin'),
    ]
    lines = read_nonempty_lines(CORRUPT_LOG)
    assert sorted(lines) == sorted(expected_corrupt), (
        f'Contents of {CORRUPT_LOG} do not match expected corrupted files. '
        f'Expected: {sorted(expected_corrupt)} Found: {sorted(lines)}'
    )

    data1 = ARTIFACTS_DIR / 'project_alpha' / 'v1' / 'data1.txt'
    assert data1.is_file(), f'{data1} was not generated.'
    assert read_nonempty_lines(data1) == ['1.2346', '-9.8765', '0.0000']

    metrics = ARTIFACTS_DIR / 'project_beta' / 'metrics.txt'
    assert metrics.is_file(), f'{metrics} was not generated.'
    assert read_nonempty_lines(metrics) == ['3.1416']


def require_regular(path, description):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f'{description} is not a regular file: {path}'


def write_valid(path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'wb') as f:
        f.write(struct.pack('<I', MAGIC))
        for value in values:
            f.write(struct.pack('<d', value))


def make_case():
    token = secrets.token_hex(10)
    root = ARTIFACTS_DIR / ('verifier_' + token) / 'nested'
    root.mkdir(parents=True)

    # Eighths are exactly representable, while the random magnitudes prevent
    # fixed-path/fixed-value implementations from satisfying the checks.
    values = [
        secrets.randbelow(20000) / 8.0 + 0.125,
        -(secrets.randbelow(20000) / 8.0 + 0.375),
        secrets.randbelow(1000) + 0.5,
    ]
    valid = root / ('measurements_' + token + '.bin')
    empty = root / ('empty_' + token + '.bin')
    bad_magic = root / ('bad_magic_' + token + '.bin')
    truncated = root / ('truncated_' + token + '.bin')
    ignored = root / ('active_' + token + '.bin.tmp')

    write_valid(valid, values)
    write_valid(empty, [])
    with open(bad_magic, 'wb') as f:
        f.write(struct.pack('<I', 0x12345678))
        f.write(struct.pack('<d', values[0]))
    with open(truncated, 'wb') as f:
        f.write(struct.pack('<I', MAGIC))
        f.write(b'\x01\x02\x03')
    write_valid(ignored, [values[1]])

    return {
        'root': root,
        'valid': {valid.with_suffix('.txt'): [format(v, '.4f') for v in values],
                  empty.with_suffix('.txt'): []},
        'corrupt': {bad_magic, truncated},
        'inputs': {valid, empty, bad_magic, truncated, ignored},
    }


def run_and_validate(executable, cases):
    original_valid = {
        ARTIFACTS_DIR / 'project_alpha' / 'v1' / 'data1.txt':
            ['1.2346', '-9.8765', '0.0000'],
        ARTIFACTS_DIR / 'project_beta' / 'metrics.txt': ['3.1416'],
    }
    original_corrupt = {
        ARTIFACTS_DIR / 'project_gamma' / 'bad_magic.bin',
        ARTIFACTS_DIR / 'project_gamma' / 'truncated.bin',
    }

    all_valid = dict(original_valid)
    all_corrupt = set(original_corrupt)
    for case in cases:
        all_valid.update(case['valid'])
        all_corrupt.update(case['corrupt'])

    # Give this invocation a clean output state so append-mode logging is
    # exercised without retaining results from the agent's earlier execution.
    if CORRUPT_LOG.exists() or CORRUPT_LOG.is_symlink():
        CORRUPT_LOG.unlink()
    for output in all_valid:
        if output.exists() or output.is_symlink():
            output.unlink()
    for corrupt in all_corrupt:
        output = corrupt.with_suffix('.txt')
        if output.exists() or output.is_symlink():
            output.unlink()

    result = subprocess.run(
        [str(executable)], cwd='/home/user', env={**os.environ, 'LC_ALL': 'C'},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f'{executable} exited with {result.returncode}. '
        f'stdout={result.stdout.decode(errors="replace")} '
        f'stderr={result.stderr.decode(errors="replace")}'
    )

    assert CORRUPT_LOG.is_file(), f'{executable} did not create {CORRUPT_LOG}'
    actual_log = read_nonempty_lines(CORRUPT_LOG)
    expected_log = [str(path.resolve()) for path in all_corrupt]
    assert sorted(actual_log) == sorted(expected_log), (
        f'Incorrect corrupt log after running {executable}. '
        f'Expected {sorted(expected_log)}, found {sorted(actual_log)}'
    )

    for output, expected in all_valid.items():
        assert output.is_file(), f'{executable} did not create {output}'
        actual = read_nonempty_lines(output)
        assert actual == expected, (
            f'Incorrect conversion in {output}: expected {expected}, found {actual}'
        )

    for corrupt in all_corrupt:
        assert not corrupt.with_suffix('.txt').exists(), (
            f'{executable} created output for corrupt file {corrupt}'
        )

    # Each randomized directory was initially empty, so any additional file is
    # evidence that a .tmp file was processed or an incorrect name was emitted.
    for case in cases:
        expected_files = set(case['inputs']) | set(case['valid'])
        actual_files = {p for p in case['root'].rglob('*') if p.is_file() or p.is_symlink()}
        assert actual_files == expected_files, (
            f'Unexpected files after running {executable}: '
            f'{sorted(map(str, actual_files - expected_files))}'
        )


check_original_final_state()
require_regular(SOURCE, 'C++ source')
require_regular(PROCESSOR, 'processor')
assert os.access(PROCESSOR, os.X_OK), f'{PROCESSOR} is not executable'
with open(PROCESSOR, 'rb') as f:
    assert f.read(4) == b'\x7fELF', f'{PROCESSOR} is not a compiled ELF binary'

# Exercise the submitted binary on a fixture unknown while the agent was running.
cases = [make_case()]
run_and_validate(PROCESSOR, cases)

# Independently compile the submitted source and exercise that build too, ensuring
# the behavior is actually implemented by process_artifacts.cpp.
fd, rebuilt_name = tempfile.mkstemp(prefix='rebuilt_processor_', dir='/tmp')
os.close(fd)
os.unlink(rebuilt_name)
compile_result = subprocess.run(
    ['g++', '-std=c++17', '-o', rebuilt_name, str(SOURCE)],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
)
assert compile_result.returncode == 0, (
    'process_artifacts.cpp did not compile: ' +
    compile_result.stderr.decode(errors='replace')
)
require_regular(Path(rebuilt_name), 'rebuilt processor')
cases.append(make_case())
run_and_validate(Path(rebuilt_name), cases)
PY_EOF

if python3 /tmp/verify_artifacts.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
