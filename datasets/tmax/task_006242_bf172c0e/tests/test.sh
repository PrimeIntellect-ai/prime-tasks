#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_symlinks_created():
    mappings = {
        '/home/user/app/input': '/home/user/real_data/input',
        '/home/user/app/output': '/home/user/real_data/output',
        '/home/user/app/logs': '/home/user/real_data/logs',
    }

    for symlink, real_dir in mappings.items():
        assert os.path.exists(real_dir), f"Real directory {real_dir} does not exist."
        assert os.path.islink(symlink), f"{symlink} is not a symlink."
        target = os.readlink(symlink)
        assert target == real_dir, f"Symlink {symlink} points to {target}, expected {real_dir}."

def test_processed_output_exists_and_correct():
    out_file = '/home/user/real_data/output/data1.txt.out'
    assert os.path.isfile(out_file), f"Output file {out_file} does not exist. Did the processor run successfully?"

    with open(out_file, 'r') as f:
        content = f.read().strip()

    expected_content = "Test data to process - PROCESSED"
    assert content == expected_content, f"Output file content is '{content}', expected '{expected_content}'."

def test_log_rotated():
    rotated_log = '/home/user/app/logs/processor.log.1'
    assert os.path.isfile(rotated_log), f"Rotated log file {rotated_log} does not exist. Did the rotation script run?"

    with open(rotated_log, 'r') as f:
        content = f.read()

    assert "INFO: Starting processing." in content, "Rotated log does not contain expected INFO messages."
    assert "ERROR: Mock error for log testing." in content, "Rotated log does not contain expected ERROR messages."

def test_error_summary_created():
    error_summary = '/home/user/app/logs/error_summary.txt'
    assert os.path.isfile(error_summary), f"Error summary file {error_summary} does not exist."

    with open(error_summary, 'r') as f:
        lines = f.readlines()

    assert len(lines) > 0, "Error summary file is empty."
    for line in lines:
        assert "ERROR" in line, f"Found non-error line in error summary: {line.strip()}"

    content = "".join(lines)
    assert "ERROR: Mock error for log testing." in content, "Error summary does not contain the expected mock error."
TEST_EOF

if (
    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    python3 << 'PY_EOF'
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

source = Path('/home/user/src/processor.cpp')
binary = Path('/home/user/app/bin/processor')
manager = Path('/home/user/service_manager.sh')
rotator = Path('/home/user/rotate_and_report.sh')

assert source.is_file(), 'processor.cpp is missing'
assert binary.is_file() and not binary.is_symlink(), 'Compiled processor is missing or is not a regular file'
assert manager.is_file() and os.access(manager, os.X_OK), 'service_manager.sh is missing or not executable'
assert rotator.is_file() and os.access(rotator, os.X_OK), 'rotate_and_report.sh is missing or not executable'
assert binary.read_bytes()[:4] == b'\x7fELF', 'processor is not a compiled ELF executable'

source_text = source.read_text()
assert 'LOG_DIR' in source_text and 'getenv' in source_text, 'Source does not read LOG_DIR from the environment'
assert '/var/log/processor.log' not in source_text, 'Source still contains the broken hardcoded log path'

rotator_text = '\n'.join(
    line for line in rotator.read_text().splitlines()
    if not line.lstrip().startswith('#')
)
assert re.search(r'\bgrep\b', rotator_text), 'Rotation script does not use grep'
assert re.search(r'\bawk\b', rotator_text), 'Rotation script does not use awk'

token = secrets.token_hex(16)
payload = 'dynamic-' + token

with tempfile.TemporaryDirectory(prefix='processor-test-') as td:
    root = Path(td)
    rebuilt = root / 'processor-rebuilt'
    subprocess.run(['g++', str(source), '-o', str(rebuilt)], check=True)
    assert rebuilt.read_bytes()[:4] == b'\x7fELF', 'Modified source did not compile to an ELF executable'

    def exercise(executable, label):
        in_dir = root / (label + '-in')
        out_dir = root / (label + '-out')
        log_dir = root / (label + '-log')
        in_dir.mkdir()
        out_dir.mkdir()
        log_dir.mkdir()
        (in_dir / 'data1.txt').write_text(payload + '\n')
        env = {
            'LOG_DIR': str(log_dir),
            'IN_DIR': str(in_dir),
            'OUT_DIR': str(out_dir),
        }
        result = subprocess.run([str(executable)], env=env, capture_output=True, text=True)
        assert result.returncode == 0, f'{label} processor failed: {result.stderr}'
        assert (out_dir / 'data1.txt.out').read_text() == payload + ' - PROCESSED', f'{label} processor did not transform dynamic input'
        log = log_dir / 'processor.log'
        assert log.is_file(), f'{label} processor did not use LOG_DIR'
        log_text = log.read_text()
        assert 'INFO: Starting processing.' in log_text
        assert 'ERROR: Mock error for log testing.' in log_text

        no_log_env = {'IN_DIR': str(in_dir), 'OUT_DIR': str(out_dir)}
        missing = subprocess.run([str(executable)], env=no_log_env, capture_output=True, text=True)
        assert missing.returncode == 1, f'{label} processor must exit with code 1 when LOG_DIR is unset'

    exercise(binary, 'submitted')
    exercise(rebuilt, 'rebuilt-source')

# Replace the executable briefly with a probe to prove that the manager executes
# the required path and exports a clean, exact environment to it.
saved_binary = Path('/tmp/processor.saved.' + token)
capture = Path('/tmp/processor.env.' + token)
shutil.copy2(binary, saved_binary)
try:
    binary.unlink()
    binary.write_text(f'''#!/bin/bash
printf '%s\\n%s\\n%s\\n%s\\n' "${{LOG_DIR-unset}}" "${{IN_DIR-unset}}" "${{OUT_DIR-unset}}" "${{LEAK_SENTINEL-unset}}" > {capture}
exec {saved_binary}
''')
    binary.chmod(0o755)

    Path('/home/user/real_data/input/data1.txt').write_text(payload + '\n')
    for path in ['/home/user/real_data/output/data1.txt.out', '/home/user/real_data/logs/processor.log']:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [str(manager)],
        env={'PATH': '/usr/bin:/bin', 'LEAK_SENTINEL': 'must-not-leak'},
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f'service manager failed: {result.stderr}'
    assert capture.is_file(), 'service manager did not execute /home/user/app/bin/processor'
    values = capture.read_text().splitlines()
    assert values == [
        '/home/user/app/logs',
        '/home/user/app/input',
        '/home/user/app/output',
        'unset',
    ], f'service manager supplied an incorrect or uncleared environment: {values}'
    assert Path('/home/user/real_data/output/data1.txt.out').read_text() == payload + ' - PROCESSED'
finally:
    try:
        binary.unlink()
    except FileNotFoundError:
        pass
    shutil.move(saved_binary, binary)
    binary.chmod(0o755)
    try:
        capture.unlink()
    except FileNotFoundError:
        pass

# Exercise rotation against unpredictable content rather than trusting the
# pre-created final-state files.
log_dir = Path('/home/user/real_data/logs')
log_dir.mkdir(parents=True, exist_ok=True)
current = log_dir / 'processor.log'
rotated = log_dir / 'processor.log.1'
summary = log_dir / 'error_summary.txt'
for path in [current, rotated, summary]:
    try:
        path.unlink()
    except FileNotFoundError:
        pass
controlled_log = (
    'INFO: begin ' + token + '\n'
    'ERROR: alpha ' + token + '\n'
    'INFO: middle\n'
    'WARN ERROR beta ' + token + '\n'
    'INFO: end\n'
)
current.write_text(controlled_log)
result = subprocess.run([str(rotator)], env={'PATH': '/usr/bin:/bin'}, capture_output=True, text=True)
assert result.returncode == 0, f'rotation script failed: {result.stderr}'
assert not current.exists(), 'processor.log was not renamed during rotation'
assert rotated.read_text() == controlled_log, 'rotated log does not preserve the original log'
expected_summary = 'ERROR: alpha ' + token + '\nWARN ERROR beta ' + token + '\n'
assert summary.read_text() == expected_summary, 'error summary was not derived correctly from dynamic log content'
PY_EOF

    # Restore the requested canonical final state and run all original assertions again.
    printf '%s\n' 'Test data to process' > /home/user/real_data/input/data1.txt
    rm -f /home/user/real_data/output/data1.txt.out \
          /home/user/real_data/logs/processor.log \
          /home/user/real_data/logs/processor.log.1 \
          /home/user/real_data/logs/error_summary.txt
    /home/user/service_manager.sh
    /home/user/rotate_and_report.sh
    python3 -m pytest /tmp/test_final_state.py -x --tb=short
) 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
