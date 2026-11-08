#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import string
import subprocess
from pathlib import Path

HOME = Path('/home/user')
CSV = HOME / 'weather_logs.csv'
SUMMARY = HOME / 'weather_summary.txt'
SEARCH_ROOTS = [Path('/home/user'), Path('/tmp'), Path('/root')]


def normalize(text):
    out = []
    previous_space = True
    for ch in text.lower():
        if ('a' <= ch <= 'z') or ('0' <= ch <= '9'):
            out.append(ch)
            previous_space = False
        elif not previous_space:
            out.append(' ')
            previous_space = True
    return ''.join(out).strip()


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def expected_summary(records):
    available = {hour: normalize(text) for hour, text in records}
    values = []
    carried = ''
    for hour in range(24):
        if hour in available:
            carried = available[hour]
        values.append(carried)

    distances = [levenshtein(values[h - 1], values[h]) for h in range(1, 24)]
    maximum = max(distances)
    end_hour = distances.index(maximum) + 1
    return (
        f'Total Missing Hours Filled: {24 - len(available)}\n'
        f'Max Levenshtein Distance: {maximum} (between hour {end_hour - 1} and hour {end_hour})\n'
        f'Average Levenshtein Distance: {sum(distances) / 23:.2f}'
    )


def write_csv(records):
    lines = ['hour,text'] + [f'{hour},{text}' for hour, text in sorted(records)]
    CSV.write_text('\n'.join(lines) + '\n')


def is_elf(path):
    try:
        if not path.is_file() or path.stat().st_size > 50 * 1024 * 1024:
            return False
        with path.open('rb') as f:
            return f.read(4) == b'\x7fELF'
    except OSError:
        return False


def discover_artifacts():
    sources = []
    executables = []
    for root in SEARCH_ROOTS:
        if not root.exists():
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {'.cache', '__pycache__', 'verifier_build'}]
            for name in files:
                path = Path(directory) / name
                try:
                    if path.suffix.lower() == '.c' and path.stat().st_size <= 1024 * 1024:
                        sources.append(path)
                    if is_elf(path) and os.access(path, os.X_OK):
                        executables.append(path)
                except OSError:
                    pass
    return list(dict.fromkeys(sources)), list(dict.fromkeys(executables))


def compile_sources(sources):
    build = Path('/var/tmp/verifier_build')
    shutil.rmtree(build, ignore_errors=True)
    build.mkdir(parents=True)
    binaries = []

    command_sets = [[source] for source in sources]
    if len(sources) > 1:
        command_sets.append(sources)

    for index, source_set in enumerate(command_sets):
        output = build / f'candidate_{index}'
        try:
            result = subprocess.run(
                ['gcc', '-std=c11', '-O2', *map(str, source_set), '-lm', '-o', str(output)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=25,
            )
            if result.returncode == 0 and is_elf(output):
                output.chmod(output.stat().st_mode | stat.S_IXUSR)
                binaries.append(output)
        except (OSError, subprocess.TimeoutExpired):
            pass
    return binaries


def candidate_passes(binary, cases):
    for records in cases:
        write_csv(records)
        try:
            SUMMARY.unlink(missing_ok=True)
            result = subprocess.run(
                [str(binary)],
                cwd=str(HOME),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=8,
            )
            if result.returncode != 0 or not SUMMARY.is_file():
                return False
            if SUMMARY.read_text().strip() != expected_summary(records):
                return False
        except (OSError, subprocess.TimeoutExpired, UnicodeError):
            return False
    return True


def make_cases():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits

    def random_text():
        pieces = []
        for _ in range(rng.randint(2, 6)):
            token = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 8)))
            pieces.append(token)
        separators = ['!!!', ' -- ', '... ', ' / ', '___', '   ']
        text = pieces[0]
        for piece in pieces[1:]:
            text += rng.choice(separators) + piece
        return rng.choice(['', '  @@ ']) + text + rng.choice(['', ' ### '])

    random_hours = {0, 23}
    while len(random_hours) < 9:
        random_hours.add(rng.randrange(24))

    return [
        [(1, '  Alpha!!!  BETA '), (2, 'alpha beta'), (5, 'gamma-9'),
         (6, 'GAMMA 9'), (10, ''), (23, 'z')],
        [(hour, random_text()) for hour in sorted(random_hours)],
        [(0, 'a'), (1, 'b'), (2, 'c')],
        [],
    ]


def test_weather_summary_exists_and_content_and_program_executes():
    # Preserve the original verifier's exact assertion for the supplied CSV.
    assert SUMMARY.is_file(), f'File {SUMMARY} does not exist. Did the C program run and generate the output?'
    expected_content = (
        'Total Missing Hours Filled: 18\n'
        'Max Levenshtein Distance: 22 (between hour 4 and hour 5)\n'
        'Average Levenshtein Distance: 3.17'
    )
    assert SUMMARY.read_text().strip() == expected_content, (
        f'Content of {SUMMARY} does not match the expected summary. Got:\n'
        f'{SUMMARY.read_text().strip()}'
    )

    original_csv = CSV.read_bytes()
    original_summary = SUMMARY.read_bytes()
    sources, existing_executables = discover_artifacts()
    assert sources, 'No C source file was found.'
    assert existing_executables, 'No compiled executable was found.'

    compiled_executables = compile_sources(sources)
    assert compiled_executables, 'The submitted C source could not be compiled.'
    cases = make_cases()

    try:
        assert any(candidate_passes(path, cases) for path in existing_executables), (
            'No pre-existing compiled executable correctly processed additional CSV inputs.'
        )
        assert any(candidate_passes(path, cases) for path in compiled_executables), (
            'No executable built from the submitted C source correctly processed additional CSV inputs.'
        )
    finally:
        CSV.write_bytes(original_csv)
        SUMMARY.write_bytes(original_summary)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
