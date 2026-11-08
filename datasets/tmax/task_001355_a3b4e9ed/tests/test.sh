#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
from collections import defaultdict
from pathlib import Path

import pytest

HOME = Path('/home/user')
INPUT = HOME / 'loc_updates.jsonl'
REJECTED = HOME / 'rejected_count.txt'
FLAGGED = HOME / 'flagged_ids.txt'


def expected_results(records):
    rejected_count = 0
    valid_updates = []

    for data in records:
        lang = data.get('lang', '')
        old_str = data.get('old', '')
        new_str = data.get('new', '')

        if (re.fullmatch(r'[a-z]{2}', lang) is None or
                not new_str or old_str == new_str):
            rejected_count += 1
        else:
            valid_updates.append(data)

    groups = defaultdict(list)
    for update in valid_updates:
        groups[(update['lang'], update['mod'])].append(update)

    flagged = set()
    for items in groups.values():
        items.sort(key=lambda x: (x['ts'], x['id']))
        rolling_window = []
        for item in items:
            old_len = len(item['old'].encode('utf-8'))
            new_len = len(item['new'].encode('utf-8'))
            rolling_window.append(new_len / (old_len + 1))
            if len(rolling_window) > 5:
                rolling_window.pop(0)
            if sum(rolling_window) / len(rolling_window) > 2.500:
                flagged.add(item['id'])

    return rejected_count, sorted(flagged)


def read_records(path):
    records = []
    with path.open('r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return records


def encode_records(records):
    return ''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in records).encode('utf-8')


def build_candidates():
    go_files = sorted(HOME.rglob('*.go'))
    assert go_files, 'No Go source file exists under /home/user.'

    main_dirs = []
    for path in go_files:
        try:
            text = path.read_text(encoding='utf-8', errors='ignore')
        except OSError:
            continue
        if re.search(r'^\s*package\s+main\b', text, re.MULTILINE):
            if path.parent not in main_dirs:
                main_dirs.append(path.parent)

    assert main_dirs, 'No Go package main was found under /home/user.'

    binaries = []
    errors = []
    for index, directory in enumerate(sorted(main_dirs, key=lambda p: (len(p.parts), str(p)))):
        binary = Path(f'/tmp/loc_submission_{index}')
        env = os.environ.copy()
        env['GO111MODULE'] = 'off'
        result = subprocess.run(
            ['go', 'build', '-o', str(binary), '.'],
            cwd=str(directory), env=env, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=60
        )
        if result.returncode == 0 and binary.is_file():
            binaries.append((binary, directory))
        else:
            errors.append(f'{directory}: {result.stdout[-2000:]}')

    assert binaries, 'No Go main package compiled successfully.\n' + '\n'.join(errors)
    return binaries


def make_hidden_fixture():
    token = secrets.token_hex(8)
    records = [
        {'ts': 1, 'lang': 'EN', 'mod': 'gate', 'id': token + '_bad_lang', 'old': 'a', 'new': 'b'},
        {'ts': 2, 'lang': 'e1', 'mod': 'gate', 'id': token + '_bad_digit', 'old': 'a', 'new': 'b'},
        {'ts': 3, 'lang': 'fr', 'mod': 'gate', 'id': token + '_empty', 'old': 'a', 'new': ''},
        {'ts': 4, 'lang': 'de', 'mod': 'gate', 'id': token + '_same', 'old': 'gleich', 'new': 'gleich'},
        {'ts': 40, 'lang': 'en', 'mod': 'ui', 'id': token + '_d', 'old': 'abc', 'new': 'xy'},
        {'ts': 10, 'lang': 'en', 'mod': 'ui', 'id': token + '_first', 'old': 'a', 'new': 'xy'},
        {'ts': 20, 'lang': 'en', 'mod': 'ui', 'id': token + '_a', 'old': 'a', 'new': 'xy'},
        {'ts': 20, 'lang': 'en', 'mod': 'ui', 'id': token + '_z', 'old': 'a', 'new': 'abcdefghijklmnopqrst'},
        {'ts': 30, 'lang': 'en', 'mod': 'ui', 'id': token + '_c', 'old': 'a', 'new': 'xy'},
        {'ts': 50, 'lang': 'en', 'mod': 'ui', 'id': token + '_e', 'old': 'a', 'new': 'xy'},
        {'ts': 60, 'lang': 'en', 'mod': 'ui', 'id': token + '_f', 'old': 'a', 'new': 'xy'},
        {'ts': 5, 'lang': 'fr', 'mod': 'bytes', 'id': token + '_utf8', 'old': 'é', 'new': 'éééé'},
        {'ts': 6, 'lang': 'fr', 'mod': 'other', 'id': token + '_separate', 'old': 'long text', 'new': 'court'},
    ]

    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    langs = ['es', 'it', 'pt']
    mods = ['menu', 'auth']
    for i in range(30):
        old_len = rng.randint(0, 8)
        new_len = rng.choice([1, 2, 3, 5, 12, 25])
        records.append({
            'ts': rng.randint(100, 112),
            'lang': rng.choice(langs),
            'mod': rng.choice(mods),
            'id': f'{token}_rnd_{i:02d}',
            'old': 'o' * old_len,
            'new': ('é' if i % 7 == 0 else 'n') * new_len,
        })
    rng.shuffle(records)
    return records


def clear_outputs():
    for path in (REJECTED, FLAGGED):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def execute_and_check(binary, cwd, records):
    fixture_bytes = encode_records(records)
    INPUT.write_bytes(fixture_bytes)
    clear_outputs()

    result = subprocess.run(
        [str(binary)], cwd=str(cwd), stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=20
    )
    assert result.returncode == 0, f'Program exited with {result.returncode}: {result.stdout}'
    assert INPUT.read_bytes() == fixture_bytes, 'Program modified the input file.'
    assert REJECTED.exists(), f'Output file {REJECTED} is missing after execution.'
    assert FLAGGED.exists(), f'Output file {FLAGGED} is missing after execution.'

    expected_rejected, expected_flagged = expected_results(records)
    actual_rejected = REJECTED.read_text(encoding='utf-8').strip()
    actual_flagged = [line.strip() for line in FLAGGED.read_text(encoding='utf-8').splitlines() if line.strip()]

    assert actual_rejected == str(expected_rejected), \
        f'Expected rejected count {expected_rejected}, got {actual_rejected!r}.'
    assert actual_flagged == expected_flagged, \
        f'Expected flagged IDs {expected_flagged}, got {actual_flagged}.'


def test_go_program_and_outputs():
    assert INPUT.exists(), f'Input file {INPUT} is missing.'
    original_bytes = INPUT.read_bytes()
    original_records = read_records(INPUT)
    hidden_records = make_hidden_fixture()
    candidates = build_candidates()
    failures = []

    try:
        for binary, cwd in candidates:
            try:
                execute_and_check(binary, cwd, hidden_records)

                # Run the compiled submission again on the original required input.
                INPUT.write_bytes(original_bytes)
                clear_outputs()
                result = subprocess.run(
                    [str(binary)], cwd=str(cwd), stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, text=True, timeout=20
                )
                assert result.returncode == 0, f'Program exited with {result.returncode}: {result.stdout}'
                assert INPUT.read_bytes() == original_bytes, 'Program modified the original input file.'

                # Preserve the original verifier's assertions on the supplied fixture.
                assert REJECTED.exists(), f'Output file {REJECTED} is missing.'
                assert FLAGGED.exists(), f'Output file {FLAGGED} is missing.'
                rejected_count, expected_flagged_ids_sorted = expected_results(original_records)
                actual_rejected = REJECTED.read_text(encoding='utf-8').strip()
                assert actual_rejected == str(rejected_count), \
                    f"Expected rejected_count.txt to contain '{rejected_count}', but got '{actual_rejected}'."
                actual_flagged = [line.strip() for line in FLAGGED.read_text(encoding='utf-8').splitlines() if line.strip()]
                assert actual_flagged == expected_flagged_ids_sorted, \
                    f'Expected flagged_ids.txt to contain {expected_flagged_ids_sorted}, but got {actual_flagged}.'
                return
            except Exception as exc:
                failures.append(f'{cwd}: {exc}')
                INPUT.write_bytes(original_bytes)

        pytest.fail('No compiled Go program passed execution tests:\n' + '\n'.join(failures))
    finally:
        INPUT.write_bytes(original_bytes)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
