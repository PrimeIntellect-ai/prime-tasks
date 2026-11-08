#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import time
import uuid
from pathlib import Path

PROJECT_DIR = Path('/home/user/shift_processor')
SCRIPT = Path('/home/user/run_benchmark.sh')
BINARY = PROJECT_DIR / 'target/release/shift_processor'
LOG = Path('/home/user/benchmark_results.log')
INPUT = Path('/home/user/data/input.csv')


def run_script(input_path):
    return subprocess.run(
        [str(SCRIPT), str(input_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def assert_single_appended_line(prefix, filename, expected_output):
    contents = LOG.read_text()
    assert contents.startswith(prefix), 'The benchmark script did not append to the existing log'
    appended = contents[len(prefix):].splitlines()
    assert len(appended) == 1, f'Expected exactly one appended line, got: {appended!r}'
    pattern = re.compile(
        rf'\[{re.escape(filename)}\] Processing completed\. '
        rf'Time: (\d+\.\d{{2}})s\. Valid Shifts: {re.escape(expected_output)}'
    )
    match = pattern.fullmatch(appended[0])
    assert match is not None, f'Unexpected log line: {appended[0]!r}'
    return float(match.group(1))


def test_rust_compilation():
    project_dir = str(PROJECT_DIR)
    assert os.path.isdir(project_dir), f'Directory missing: {project_dir}'
    result = subprocess.run(
        ['cargo', 'build', '--release'],
        cwd=project_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f'Cargo build failed:\n{result.stderr}'


def test_benchmark_script_exists_and_executable():
    assert SCRIPT.is_file(), f'Script missing: {SCRIPT}'
    assert os.access(SCRIPT, os.X_OK), f'Script is not executable: {SCRIPT}'


def test_benchmark_script_execution_and_log_format():
    assert SCRIPT.is_file(), f'Script missing: {SCRIPT}'
    assert INPUT.is_file(), f'Input CSV missing: {INPUT}'
    assert BINARY.is_file(), f'Release binary missing: {BINARY}'

    binary_result = subprocess.run(
        [str(BINARY), str(INPUT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert binary_result.returncode == 0, binary_result.stderr
    expected_output = binary_result.stdout.strip()
    assert expected_output == '2', f'Unexpected Rust output: {expected_output!r}'

    prefix = 'preexisting benchmark entry\n'
    LOG.write_text(prefix)
    result = run_script(INPUT)
    assert result.returncode == 0, f'Benchmark script failed to run:\n{result.stderr}'
    assert LOG.is_file(), f'Log file was not created: {LOG}'
    assert_single_appended_line(prefix, INPUT.name, expected_output)


def test_script_really_invokes_and_times_release_binary():
    assert BINARY.is_file(), f'Release binary missing: {BINARY}'
    backup = BINARY.with_name(f'.shift_processor.backup.{uuid.uuid4().hex}')
    os.replace(BINARY, backup)

    try:
        measured_times = []
        for delay in (0.12, 0.27):
            token = str(10000 + int(uuid.uuid4().hex[:6], 16) % 80000)
            recorder = Path(f'/tmp/shift_probe_{uuid.uuid4().hex}')
            input_path = Path(f'/tmp/shifts_{uuid.uuid4().hex}.csv')
            input_path.write_text('probe,1,2\n')

            probe = f'''#!/bin/bash
printf '%s\\n' "$#" "$@" > {recorder}
sleep {delay}
printf '%s\\n' {token}
'''
            BINARY.write_text(probe)
            BINARY.chmod(0o755)

            prefix = f'existing-{uuid.uuid4().hex}\n'
            LOG.write_text(prefix)
            wall_start = time.monotonic()
            result = run_script(input_path)
            wall_elapsed = time.monotonic() - wall_start

            assert result.returncode == 0, f'Benchmark script failed with probe binary:\n{result.stderr}'
            assert recorder.is_file(), 'The release binary was not invoked by the benchmark script'
            invocation = recorder.read_text().splitlines()
            assert invocation == ['1', str(input_path)], (
                f'Release binary received incorrect arguments: {invocation!r}'
            )

            reported = assert_single_appended_line(prefix, input_path.name, token)
            assert reported >= delay - 0.04, (
                f'Reported time {reported:.2f}s does not include the binary execution delay {delay:.2f}s'
            )
            assert reported <= wall_elapsed + 0.10, (
                f'Reported time {reported:.2f}s exceeds observed script runtime {wall_elapsed:.2f}s'
            )
            measured_times.append(reported)

            recorder.unlink(missing_ok=True)
            input_path.unlink(missing_ok=True)

        assert measured_times[1] > measured_times[0], (
            f'Reported times do not track differing binary runtimes: {measured_times!r}'
        )
    finally:
        BINARY.unlink(missing_ok=True)
        os.replace(backup, BINARY)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
