#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

HOME = Path('/home/user')


def test_cleaned_small_txt_content():
    path = HOME / 'cleaned_small.txt'
    assert path.is_file(), f'File {path} does not exist.'
    content = path.read_text()
    expected = 'hello world this is a test data cleaning is fun 123'
    assert content.strip() == expected, f'Content of {path} does not match the expected cleaned output. Got: {content!r}'


def test_times_txt_exists_and_format():
    path = HOME / 'times.txt'
    assert path.is_file(), f'File {path} does not exist.'
    lines = path.read_text().strip().split('\n')
    assert len(lines) == 30, f'Expected exactly 30 lines in {path}, got {len(lines)}.'
    for i, line in enumerate(lines):
        assert line.isdigit(), f'Line {i+1} in {path} is not an integer: {line!r}'


def test_benchmark_stats_format():
    path = HOME / 'benchmark_stats.txt'
    assert path.is_file(), f'File {path} does not exist.'
    content = path.read_text().strip()
    pattern = r'^Mean: \d+\.\d{2} ms, 95% CI: \[\d+\.\d{2} ms, \d+\.\d{2} ms\]$'
    assert re.match(pattern, content), f'Content of {path} does not match the expected format. Got: {content!r}'


def test_executables_and_scripts_exist():
    expected_files = [
        HOME / 'tokenizer.c',
        HOME / 'tokenizer',
        HOME / 'benchmark.sh',
        HOME / 'stats.c',
        HOME / 'stats',
    ]
    for path in expected_files:
        assert path.is_file(), f'Expected file/executable {path} does not exist.'
        if not str(path).endswith('.c') and not str(path).endswith('.txt'):
            assert os.access(path, os.X_OK), f'Expected {path} to be executable.'

    for path in (HOME / 'tokenizer', HOME / 'stats'):
        assert path.read_bytes()[:4] == b'\x7fELF', f'{path} is not a compiled native executable.'


def clean_reference(data: bytes) -> bytes:
    out = bytearray()
    pending_space = False
    started = False
    for value in data:
        if 65 <= value <= 90:
            value += 32
        valid_alnum = 97 <= value <= 122 or 48 <= value <= 57
        if valid_alnum:
            if pending_space and started:
                out.append(32)
            out.append(value)
            started = True
            pending_space = False
        elif value == 32:
            if started:
                pending_space = True
        else:
            if started:
                pending_space = True
    return bytes(out)


def compile_c(source: Path, output: Path):
    result = subprocess.run(
        ['gcc', '-O2', '-std=c11', str(source), '-lm', '-o', str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, f'Failed to compile {source}:\n{result.stderr.decode(errors="replace")}'


def exercise_tokenizer(executable: Path, work: Path):
    cases = [
        b'   MIXED Case!! tabs\tand\nlines---42  ',
        b'...A@@@B___C   001!!!',
        b'\xff\xfe Hello\r\nWORLD \x80 9 ',
        os.urandom(48) + b' SecretABC 123 z-Z ',
        b'       !!!\n\t...',
    ]
    for index, data in enumerate(cases):
        source = work / f'input_{index}.bin'
        output = work / f'output_{index}.bin'
        source.write_bytes(data)
        result = subprocess.run([str(executable), str(source), str(output)], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, f'{executable} failed on a valid invocation: {result.stderr!r}'
        assert output.is_file(), f'{executable} did not create its requested output file.'
        assert output.read_bytes() == clean_reference(data), f'{executable} produced incorrect cleaned output.'

    for args in ([], [str(work / 'input_0.bin')],
                 [str(work / 'input_0.bin'), str(work / 'extra.out'), 'extra']):
        result = subprocess.run([str(executable), *args], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=5)
        assert result.returncode != 0, f'{executable} accepted an invocation without exactly two arguments.'


def test_tokenizer_on_unseen_inputs_and_from_source():
    with tempfile.TemporaryDirectory(prefix='verify_tokenizer_') as directory:
        work = Path(directory)
        rebuilt = work / 'tokenizer_from_source'
        compile_c(HOME / 'tokenizer.c', rebuilt)
        exercise_tokenizer(HOME / 'tokenizer', work)
        exercise_tokenizer(rebuilt, work)


def expected_stats(values):
    count = len(values)
    mean = sum(values) / count
    variance = sum((value - mean) ** 2 for value in values) / (count - 1)
    stddev = math.sqrt(variance)
    margin = 1.96 * stddev / math.sqrt(count)
    return f'Mean: {mean:.2f} ms, 95% CI: [{mean-margin:.2f} ms, {mean+margin:.2f} ms]'


def test_stats_recomputes_results_and_source_builds():
    times_path = HOME / 'times.txt'
    stats_path = HOME / 'benchmark_stats.txt'
    old_times = times_path.read_bytes() if times_path.exists() else None
    old_stats = stats_path.read_bytes() if stats_path.exists() else None
    rng = random.SystemRandom()
    values = [rng.randrange(80, 900) for _ in range(30)]
    expected = expected_stats(values)

    try:
        with tempfile.TemporaryDirectory(prefix='verify_stats_') as directory:
            rebuilt = Path(directory) / 'stats_from_source'
            compile_c(HOME / 'stats.c', rebuilt)
            for executable in (HOME / 'stats', rebuilt):
                times_path.write_text(''.join(f'{value}\n' for value in values))
                if stats_path.exists():
                    stats_path.unlink()
                result = subprocess.run([str(executable)], cwd=str(HOME), stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, timeout=10)
                assert result.returncode == 0, f'{executable} failed: {result.stderr!r}'
                assert stats_path.is_file(), f'{executable} did not create benchmark_stats.txt.'
                assert stats_path.read_text().strip() == expected, (
                    f'{executable} did not compute the statistics from the supplied values. '
                    f'Expected {expected!r}, got {stats_path.read_text().strip()!r}'
                )
    finally:
        if old_times is None:
            times_path.unlink(missing_ok=True)
        else:
            times_path.write_bytes(old_times)
        if old_stats is None:
            stats_path.unlink(missing_ok=True)
        else:
            stats_path.write_bytes(old_stats)


def test_benchmark_executes_tokenizer_exactly_30_times_and_measures_it():
    tokenizer = HOME / 'tokenizer'
    times_path = HOME / 'times.txt'
    old_tokenizer = tokenizer.read_bytes()
    old_mode = stat.S_IMODE(tokenizer.stat().st_mode)
    old_times = times_path.read_bytes() if times_path.exists() else None

    with tempfile.TemporaryDirectory(prefix='verify_benchmark_') as directory:
        work = Path(directory)
        real_tokenizer = work / 'real_tokenizer'
        real_tokenizer.write_bytes(old_tokenizer)
        real_tokenizer.chmod(0o755)
        counter = work / 'counter'
        counter.write_text('0\n')
        lock = work / 'lock'
        log = work / 'calls.log'
        delays = [random.SystemRandom().randrange(40, 181) for _ in range(30)]
        delay_file = work / 'delays'
        delay_file.write_text(''.join(f'{value}\n' for value in delays))

        wrapper = f'''#!/bin/bash
if [ "$#" -ne 2 ]; then
  exit 97
fi
exec 9>{shlex.quote(str(lock))}
flock 9
n=$(cat {shlex.quote(str(counter))})
n=$((n + 1))
echo "$n" > {shlex.quote(str(counter))}
delay_ms=$(sed -n "${{n}}p" {shlex.quote(str(delay_file))})
flock -u 9
[ -n "$delay_ms" ] || exit 98
start=$(date +%s%3N)
sleep "$(printf '0.%03d' "$delay_ms")"
{shlex.quote(str(real_tokenizer))} "$@"
rc=$?
end=$(date +%s%3N)
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$start" "$end" "$rc" "$1" "$2" >> {shlex.quote(str(log))}
exit "$rc"
'''
        try:
            tokenizer.write_text(wrapper)
            tokenizer.chmod(0o755)
            times_path.unlink(missing_ok=True)
            result = subprocess.run([str(HOME / 'benchmark.sh')], cwd=str(HOME),
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
            assert result.returncode == 0, f'benchmark.sh failed: {result.stderr.decode(errors="replace")}'
            assert tokenizer.read_text() == wrapper, 'benchmark.sh replaced or bypassed the instrumented tokenizer.'

            calls = log.read_text().strip().splitlines() if log.exists() else []
            assert len(calls) == 30, f'benchmark.sh invoked the tokenizer {len(calls)} times instead of exactly 30.'
            parsed_calls = []
            for expected_number, line in enumerate(calls, 1):
                fields = line.split('\t')
                assert len(fields) == 6, f'Malformed tokenizer invocation record: {line!r}'
                number, start, end, rc, input_path, output_path = fields
                assert int(number) == expected_number
                assert rc == '0'
                assert input_path == '/home/user/raw_large.txt'
                assert output_path == '/dev/null'
                parsed_calls.append(int(end) - int(start))

            lines = times_path.read_text().strip().splitlines()
            assert len(lines) == 30
            assert all(line.isdigit() for line in lines)
            observed = [int(line) for line in lines]
            for index, (reported, internal) in enumerate(zip(observed, parsed_calls), 1):
                assert internal - 15 <= reported <= internal + 300, (
                    f'Run {index} timing ({reported} ms) does not reflect its measured wall time ({internal} ms).'
                )
        finally:
            tokenizer.write_bytes(old_tokenizer)
            tokenizer.chmod(old_mode)
            if old_times is None:
                times_path.unlink(missing_ok=True)
            else:
                times_path.write_bytes(old_times)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
