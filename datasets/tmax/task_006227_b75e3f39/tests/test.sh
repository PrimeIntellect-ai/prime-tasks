#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/loc_processor')
INPUT = Path('/home/user/raw_translations.jsonl')
NORMALIZED = Path('/home/user/normalized_translations.jsonl')
STATS = Path('/home/user/locale_stats.json')

ORIGINAL_INPUT = '''{"id": "m1", "locale": "es_ES", "content": "El resultado de $ 2 + 2 $ es 4."}
{"id": "m2", "locale": "es_ES", "content": "Calcular $x = y * ( z - 1 ) / 2$"}
{"id": "m3", "locale": "fr_FR", "content": "L'équation $E = m * c^2$ est célèbre."}
{"id": "m4", "locale": "fr_FR", "content": "Sans maths ici."}
{"id": "m5", "locale": "en_US", "content": "Let $ f(x) = x^2 - 4 * x + 4 $ and $ y = 0 $"}
'''


def run_program():
    for path in (NORMALIZED, STATS):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--bin', 'loc_processor'],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'Rust application failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def compute_expected_results(input_path):
    expected_normalized = []
    stats = {}

    with open(input_path, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            msg_id = data['id']
            locale = data['locale']
            content = data['content']

            math_blocks = re.findall(r'\$(.*?)\$', content)

            def replace_math(match):
                inner = match.group(1)
                inner_no_ws = re.sub(r'\s+', '', inner)
                return f'${inner_no_ws}$'

            normalized_content = re.sub(r'\$(.*?)\$', replace_math, content)
            expected_normalized.append({
                'id': msg_id,
                'locale': locale,
                'normalized_content': normalized_content,
            })

            complexity = 0
            for block in math_blocks:
                complexity += sum(block.count(op) for op in ['+', '-', '*', '/', '='])

            text_only = re.sub(r'\$.*?\$', '', content)
            text_length = len(text_only.strip())

            if locale not in stats:
                stats[locale] = {
                    'message_count': 0,
                    'total_text_length': 0,
                    'max_math_complexity': 0,
                }

            stats[locale]['message_count'] += 1
            stats[locale]['total_text_length'] += text_length
            stats[locale]['max_math_complexity'] = max(
                stats[locale]['max_math_complexity'], complexity
            )

    expected_stats = {}
    for loc, values in stats.items():
        avg_len = values['total_text_length'] / values['message_count']
        expected_stats[loc] = {
            'message_count': values['message_count'],
            'avg_text_length': round(avg_len, 2),
            'max_math_complexity': values['max_math_complexity'],
        }

    return expected_normalized, expected_stats


def compute_general_expected(records):
    expected_normalized = []
    aggregate = {}

    for data in records:
        content = data['content']
        blocks = re.findall(r'\$(.*?)\$', content, flags=re.DOTALL)
        normalized = re.sub(
            r'\$(.*?)\$',
            lambda match: '$' + re.sub(r'\s+', '', match.group(1)) + '$',
            content,
            flags=re.DOTALL,
        )
        expected_normalized.append({
            'id': data['id'],
            'locale': data['locale'],
            'normalized_content': normalized,
        })

        complexity = sum(
            sum(block.count(op) for op in ['+', '-', '*', '/', '='])
            for block in blocks
        )
        text_length = len(re.sub(r'\$.*?\$', '', content, flags=re.DOTALL).strip())
        entry = aggregate.setdefault(data['locale'], [0, 0, 0])
        entry[0] += 1
        entry[1] += text_length
        entry[2] = max(entry[2], complexity)

    expected_stats = {
        locale: {
            'message_count': values[0],
            'avg_text_length': round(values[1] / values[0], 2),
            'max_math_complexity': values[2],
        }
        for locale, values in aggregate.items()
    }
    return expected_normalized, expected_stats


def read_outputs():
    assert NORMALIZED.exists(), f'Output file {NORMALIZED} does not exist.'
    assert STATS.exists(), f'Output file {STATS} does not exist.'

    actual_normalized = []
    with NORMALIZED.open('r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            try:
                actual_normalized.append(json.loads(line))
            except json.JSONDecodeError:
                assert False, f'Invalid JSON line in {NORMALIZED}: {line}'

    with STATS.open('r', encoding='utf-8') as f:
        try:
            actual_stats = json.load(f)
        except json.JSONDecodeError:
            assert False, f'Invalid JSON in {STATS}'
    return actual_normalized, actual_stats


def assert_outputs(expected_normalized, expected_stats):
    actual_normalized, actual_stats = read_outputs()
    assert actual_normalized == expected_normalized
    assert set(actual_stats.keys()) == set(expected_stats.keys())
    for locale, expected in expected_stats.items():
        actual = actual_stats[locale]
        assert actual.get('message_count') == expected['message_count']
        assert actual.get('max_math_complexity') == expected['max_math_complexity']
        actual_avg = actual.get('avg_text_length')
        assert actual_avg is not None
        assert isinstance(actual_avg, (int, float)) and not isinstance(actual_avg, bool)
        assert abs(actual_avg - expected['avg_text_length']) < 0.02


@pytest.fixture(scope='session', autouse=True)
def verify_rust_project_and_restore_fixture():
    assert PROJECT.is_dir(), f'Missing Rust project directory {PROJECT}'
    cargo_toml = PROJECT / 'Cargo.toml'
    main_rs = PROJECT / 'src' / 'main.rs'
    assert cargo_toml.is_file(), 'Missing Cargo.toml'
    assert main_rs.is_file(), 'Missing src/main.rs'

    manifest = cargo_toml.read_text(encoding='utf-8')
    package_section = re.search(r'(?ms)^\s*\[package\]\s*(.*?)(?=^\s*\[|\Z)', manifest)
    assert package_section, 'Cargo.toml has no [package] section'
    assert re.search(r'(?m)^\s*name\s*=\s*["\']loc_processor["\']\s*$', package_section.group(1)), \
        'Rust package must be named loc_processor'
    assert re.search(r'(?m)^\s*regex\s*=', manifest), \
        'Cargo.toml must declare the regex crate'

    rust_files = list((PROJECT / 'src').rglob('*.rs'))
    assert rust_files, 'Project contains no Rust source files'
    source = '\n'.join(path.read_text(encoding='utf-8') for path in rust_files)
    assert re.search(r'\bBufReader\b', source), \
        'Rust source must use buffered streaming input'
    assert re.search(r'\.lines\s*\(|\bread_line\s*\(', source), \
        'Rust source must process the input line-by-line'
    assert re.search(r'(?:regex\s*::\s*)?Regex(?:Builder)?\b', source), \
        'Rust source must use regular expressions'

    build = subprocess.run(
        ['cargo', 'build', '--quiet', '--bin', 'loc_processor'],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, (
        f'Rust project does not compile\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}'
    )

    INPUT.write_text(ORIGINAL_INPUT, encoding='utf-8')
    run_program()
    try:
        yield
    finally:
        INPUT.write_text(ORIGINAL_INPUT, encoding='utf-8')
        for path in (NORMALIZED, STATS):
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        subprocess.run(
            ['cargo', 'run', '--quiet', '--bin', 'loc_processor'],
            cwd=PROJECT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=120,
        )


def test_original_normalized_translations_and_locale_stats():
    input_path = '/home/user/raw_translations.jsonl'
    output_path = '/home/user/normalized_translations.jsonl'
    stats_path = '/home/user/locale_stats.json'

    assert os.path.exists(output_path), f'Output file {output_path} does not exist.'
    expected_normalized, expected_stats = compute_expected_results(input_path)

    actual_normalized = []
    with open(output_path, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            try:
                actual_normalized.append(json.loads(line))
            except json.JSONDecodeError:
                assert False, f'Invalid JSON line in {output_path}: {line}'

    assert len(actual_normalized) == len(expected_normalized), f'Expected {len(expected_normalized)} lines, found {len(actual_normalized)}'
    for expected, actual in zip(expected_normalized, actual_normalized):
        assert actual.get('id') == expected['id'], f"Expected id {expected['id']}, got {actual.get('id')}"
        assert actual.get('locale') == expected['locale'], f"Expected locale {expected['locale']}, got {actual.get('locale')}"
        assert actual.get('normalized_content') == expected['normalized_content'], f"Content mismatch for id {expected['id']}. Expected: {expected['normalized_content']}, Got: {actual.get('normalized_content')}"

    assert os.path.exists(stats_path), f'Output file {stats_path} does not exist.'
    with open(stats_path, 'r', encoding='utf-8') as f:
        try:
            actual_stats = json.load(f)
        except json.JSONDecodeError:
            assert False, f'Invalid JSON in {stats_path}'

    assert set(actual_stats.keys()) == set(expected_stats.keys()), f'Locales mismatch. Expected {set(expected_stats.keys())}, got {set(actual_stats.keys())}'
    for loc, expected in expected_stats.items():
        actual = actual_stats[loc]
        assert actual.get('message_count') == expected['message_count'], f'Message count mismatch for {loc}'
        assert actual.get('max_math_complexity') == expected['max_math_complexity'], f'Max math complexity mismatch for {loc}'
        actual_avg = actual.get('avg_text_length')
        assert actual_avg is not None, f'Missing avg_text_length for {loc}'
        assert abs(actual_avg - expected['avg_text_length']) < 0.02, f"Avg text length mismatch for {loc}. Expected {expected['avg_text_length']}, got {actual_avg}"


@pytest.mark.parametrize('round_number', [1, 2])
def test_application_on_unpredictable_inputs(round_number):
    token = secrets.token_hex(8)
    locales = [f'qa_{token[:4]}', f'zz_{token[4:8]}', f'ux_{token[8:12]}']
    records = [
        {'id': f'{token}-plain', 'locale': locales[0], 'content': f'  Unicode café {token} sans formule.  '},
        {'id': f'{token}-tabs', 'locale': locales[1], 'content': 'Avant $\t α +  β\u2003= γ $ après'},
        {'id': f'{token}-multi', 'locale': locales[2], 'content': 'A $ x / y - 2 $ B $p*q+7=9$ C'},
        {'id': f'{token}-newline', 'locale': locales[1], 'content': 'Début $ a +\n b = c $ fin'},
        {'id': f'{token}-onlymath', 'locale': locales[0], 'content': '$ 8 * 7 / 2 - 1 = 27 $'},
    ]

    for i in range(173 + round_number):
        locale = locales[i % len(locales)]
        mode = i % 4
        if mode == 0:
            content = f'Préfixe {token}-{i} $ v{i} + 2 = w{i} $ suffixe'
        elif mode == 1:
            content = f'$a{i}*b{i}/c{i}-d{i}$ trailing {i}'
        elif mode == 2:
            content = f'No mathematics here: {token}:{i}'
        else:
            content = f'left $ q{i} +\t r{i} $ middle $s{i}=t{i}*3$ right'
        records.append({'id': f'{token}-{i}', 'locale': locale, 'content': content})

    with INPUT.open('w', encoding='utf-8') as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=False) + '\n')

    expected_normalized, expected_stats = compute_general_expected(records)
    run_program()
    assert_outputs(expected_normalized, expected_stats)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
