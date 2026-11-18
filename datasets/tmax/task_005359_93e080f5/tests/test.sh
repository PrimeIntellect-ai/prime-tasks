#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_loc.py
import json
import math
import os
import random
import re
import secrets
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

RAW = Path('/home/user/loc_data/raw_logs.txt')
ERROR = Path('/home/user/loc_data/error.log')
STATS = Path('/home/user/loc_data/stats.json')
PATTERN = re.compile(r'^\[(.*?)\] LANG:(.*?) \| SRC:(.*?) \| TR:(.*?)$')


def expected_for(raw_bytes):
    text = raw_bytes.decode('utf-8')
    errors = []
    translations = defaultdict(list)
    for line in text.splitlines(keepends=True):
        body = line[:-1] if line.endswith('\n') else line
        match = PATTERN.match(body)
        if not match:
            errors.append(line)
            continue
        timestamp, lang, src, tr = match.groups()
        translations[lang].append((timestamp, src, tr))

    stats = {}
    for lang, items in translations.items():
        items.sort(key=lambda item: item[0])
        ratios = [0.0 if not src else len(tr) / len(src)
                  for _, src, tr in items[-3:]]
        stats[lang] = round(sum(ratios) / len(ratios), 4) if ratios else 0.0
    return ''.join(errors).encode('utf-8'), stats


def number_token(value):
    return ('NUMBER', value)


def check_outputs(raw_bytes):
    expected_errors, expected_stats = expected_for(raw_bytes)

    assert RAW.exists(), f'Input file {RAW} missing.'
    assert ERROR.exists(), f'Error log {ERROR} was not created.'
    assert ERROR.read_bytes() == expected_errors, \
        'error.log does not contain the exact malformed lines from raw_logs.txt.'

    assert STATS.exists(), f'Output file {STATS} was not created.'
    content = STATS.read_text(encoding='utf-8')
    try:
        pairs = json.loads(
            content,
            object_pairs_hook=lambda values: values,
            parse_float=number_token,
            parse_int=number_token,
            parse_constant=lambda value: ('INVALID', value),
        )
    except json.JSONDecodeError as exc:
        raise AssertionError('stats.json is not valid JSON.') from exc

    assert isinstance(pairs, list), 'stats.json must contain a JSON object.'
    keys = [key for key, _ in pairs]
    assert len(keys) == len(set(keys)), 'stats.json contains duplicate language keys.'
    assert keys == sorted(keys), 'Language keys in stats.json are not sorted alphabetically.'
    assert sorted(keys) == sorted(expected_stats.keys()), \
        'Language keys in stats.json do not match expected languages.'

    actual = dict(pairs)
    for lang, expected_value in expected_stats.items():
        token = actual[lang]
        assert isinstance(token, tuple) and token[0] == 'NUMBER', \
            f'Value for {lang} is not a JSON number.'
        spelling = token[1]
        assert re.fullmatch(r'-?\d+\.\d{4}', spelling), \
            f'Value for {lang} is not displayed with exactly four decimal places.'
        value = float(spelling)
        assert math.isclose(value, expected_value, rel_tol=1e-5, abs_tol=1e-4), \
            f'Value for {lang} is incorrect. Expected {expected_value}, got {value}.'


def run_case(executable, raw_bytes):
    RAW.parent.mkdir(parents=True, exist_ok=True)
    RAW.write_bytes(raw_bytes)
    for output in (ERROR, STATS):
        try:
            output.unlink()
        except FileNotFoundError:
            pass
    subprocess.run([str(executable)], cwd=str(executable.parent), check=True,
                   timeout=8, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    check_outputs(raw_bytes)


def dynamic_fixture():
    nonce = secrets.token_hex(4)
    languages = [f'aa-{nonce}', f'mm-{nonce}', f'zz-{nonce}']
    records = []
    for language_index, language in enumerate(languages):
        count = 2 if language_index == 1 else 6
        for index in range(count):
            src_len = 2 + secrets.randbelow(11)
            tr_len = secrets.randbelow(18)
            src = chr(65 + language_index) * src_len
            tr = chr(107 + language_index) * tr_len
            if language_index == 0 and index == 4:
                src = ''
            if language_index == 2 and index == 5:
                tr = ''
            minute = language_index * 10 + index
            records.append(
                f'[2024-02-03T12:{minute:02d}:00Z] LANG:{language} | SRC:{src} | TR:{tr}\n'
            )

    random.SystemRandom().shuffle(records)
    records.insert(1, f'[BROKEN-{nonce}] missing fields\n')
    records.append(f'[2024-02-03T13:00:00Z] LANG:{nonce} | SRC:not-enough-separators\n')
    records.append(f'plain malformed {nonce}')
    return ''.join(records).encode('utf-8')


def find_sources():
    roots = [Path('/home/user'), Path('/root'), Path('/workspace')]
    sources = []
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob('*.cpp'):
            if path.is_file() and '/tests/' not in str(path):
                sources.append(path)
    return sorted(set(sources))


assert RAW.exists(), f'Input file {RAW} missing.'
original_raw = RAW.read_bytes()
sources = find_sources()
assert sources, 'No C++ source file was created.'

dynamic_raw = dynamic_fixture()
failures = []
for index, source in enumerate(sources):
    executable = Path(f'/tmp/loc_analyzer_{index}_{secrets.token_hex(4)}')
    try:
        compile_result = subprocess.run(
            ['g++', '-std=c++17', str(source), '-o', str(executable)],
            timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        if compile_result.returncode != 0:
            failures.append(f'{source}: compilation failed')
            continue
        assert executable.is_file() and os.access(executable, os.X_OK), \
            'Compilation did not produce an executable.'

        # Preserve the original verifier's checks on the supplied input, then
        # exercise the compiled program on an unpredictable second input.
        run_case(executable, original_raw)
        run_case(executable, dynamic_raw)

        # Leave the required outputs corresponding to the supplied log fixture.
        run_case(executable, original_raw)
        sys.exit(0)
    except Exception as exc:
        failures.append(f'{source}: {exc}')
    finally:
        try:
            executable.unlink()
        except FileNotFoundError:
            pass

RAW.write_bytes(original_raw)
raise AssertionError('No submitted C++ program passed execution tests. ' + '; '.join(failures))
PY_EOF

if python3 /tmp/verify_loc.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
