#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import json
import os
import re
import secrets
import shutil
import subprocess
from pathlib import Path

RAW = Path('/home/user/raw_translations.jsonl')
PROCESSED = Path('/home/user/processed')
ROLLING = Path('/home/user/es-ES_rolling_avg.txt')


def read_jsonl(path):
    assert path.is_file(), f'{path} is missing'
    raw_lines = [line for line in path.read_bytes().splitlines() if line.strip()]
    for number, line in enumerate(raw_lines, 1):
        assert not re.search(rb'\\u[0-9a-fA-F]{4}', line), (
            f'{path}, line {number}, contains a JSON Unicode escape instead of literal UTF-8'
        )
    result = []
    for number, line in enumerate(raw_lines, 1):
        try:
            result.append(json.loads(line.decode('utf-8')))
        except Exception as exc:
            raise AssertionError(f'{path}, line {number}, is not valid UTF-8 JSON: {exc}')
    return result


def check_original_outputs():
    assert PROCESSED.is_dir(), 'The /home/user/processed directory was not created.'
    es_path = PROCESSED / 'es-ES.jsonl'
    fr_path = PROCESSED / 'fr-FR.jsonl'
    assert es_path.is_file(), 'The es-ES.jsonl file is missing.'
    assert fr_path.is_file(), 'The fr-FR.jsonl file is missing.'
    assert ROLLING.is_file(), 'The es-ES_rolling_avg.txt file is missing.'

    expected_es = [
        {'timestamp': 1600000002, 'string_id': 'txt_desc', 'locale': 'es-ES', 'text': 'A é B'},
        {'timestamp': 1600000003, 'string_id': 'btn_cancel', 'locale': 'es-ES', 'text': 'X'},
        {'timestamp': 1600000004, 'string_id': 'btn_greet', 'locale': 'es-ES', 'text': 'Hol á'},
        {'timestamp': 1600000006, 'string_id': 'btn_help', 'locale': 'es-ES', 'text': '¡Ojo!'},
    ]
    expected_fr = [
        {'timestamp': 1600000001, 'string_id': 'btn_greet', 'locale': 'fr-FR', 'text': 'Oui ça'}
    ]
    assert read_jsonl(es_path) == expected_es, 'Incorrect es-ES processed content or ordering'
    assert read_jsonl(fr_path) == expected_fr, 'Incorrect fr-FR processed content or ordering'

    averages = [line.strip() for line in ROLLING.read_text(encoding='utf-8').splitlines() if line.strip()]
    assert averages == ['5.0', '3.0', '3.7', '3.7'], 'Incorrect es-ES rolling averages'


def script_candidates():
    roots = [Path('/home/user'), Path('/root'), Path('/workspace'), Path('/tmp')]
    excluded_dirs = {'processed', '.cache', '.local', '.npm', '.git', '__pycache__', 'tests', 'logs'}
    found = []
    for root in roots:
        if not root.exists():
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in excluded_dirs]
            for name in files:
                path = Path(current) / name
                if path == Path('/tmp/verify_task.py'):
                    continue
                try:
                    if not path.is_file() or path.stat().st_size > 1024 * 1024:
                        continue
                    first = path.open('rb').readline(256).decode('utf-8', 'ignore')
                    if path.suffix == '.sh' or (first.startswith('#!') and 'bash' in first):
                        found.append(path)
                except OSError:
                    pass
    return sorted(set(found), key=lambda p: str(p))


def parallel_style(source):
    code = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith('#'))
    if re.search(r'\bparallel\b', code):
        return 'parallel'
    if re.search(r'\bxargs\b[^\n]*(?:\s-P(?:\s*\d+)?|--max-procs(?:=|\s))', code):
        return 'xargs'
    if re.search(r'(?<![&>])&(?![&0-9])(?:\s|$)', code) and re.search(r'\bwait\b', code):
        return 'background'
    return None


def write_dynamic_input(base, suffix):
    records = [
        {'timestamp': base + 1, 'string_id': 'old-' + suffix, 'locale': 'es-ES', 'text': 'Viejo \\u00e1'},
        {'timestamp': base + 5, 'string_id': 'old-' + suffix, 'locale': 'es-ES', 'text': 'N\\u00f1'},
        {'timestamp': base + 2, 'string_id': 'hello-' + suffix, 'locale': 'es-ES', 'text': '\\u00a1Hola!'},
        {'timestamp': base + 4, 'string_id': 'cat-' + suffix, 'locale': 'es-ES', 'text': '\\u732b \\u00e9'},
        {'timestamp': base + 3, 'string_id': 'other-' + suffix, 'locale': 'fr-FR', 'text': 'Gar\\u00e7on'},
        {'timestamp': base + 6, 'string_id': 'other-' + suffix, 'locale': 'fr-FR', 'text': 'Fran\\u00e7ais'},
    ]
    with RAW.open('w', encoding='utf-8', newline='\n') as out:
        for record in records:
            out.write(json.dumps(record, ensure_ascii=False, separators=(',', ':')) + '\n')

    expected_es = [
        {'timestamp': base + 2, 'string_id': 'hello-' + suffix, 'locale': 'es-ES', 'text': '¡Hola!'},
        {'timestamp': base + 4, 'string_id': 'cat-' + suffix, 'locale': 'es-ES', 'text': '猫 é'},
        {'timestamp': base + 5, 'string_id': 'old-' + suffix, 'locale': 'es-ES', 'text': 'Nñ'},
    ]
    expected_fr = [
        {'timestamp': base + 6, 'string_id': 'other-' + suffix, 'locale': 'fr-FR', 'text': 'Français'}
    ]
    return expected_es, expected_fr


def check_dynamic_outputs(expected_es, expected_fr):
    assert read_jsonl(PROCESSED / 'es-ES.jsonl') == expected_es
    assert read_jsonl(PROCESSED / 'fr-FR.jsonl') == expected_fr
    assert ROLLING.is_file(), 'Dynamic run did not create the rolling-average file'
    averages = [line.strip() for line in ROLLING.read_text(encoding='utf-8').splitlines() if line.strip()]
    assert averages == ['6.0', '4.5', '3.7'], f'Incorrect dynamic rolling averages: {averages}'


def check_pipeline_execution():
    candidates = []
    for path in script_candidates():
        try:
            source = path.read_text(encoding='utf-8')
        except (OSError, UnicodeError):
            continue
        style = parallel_style(source)
        if style:
            candidates.append((path, style))

    assert candidates, 'No Bash pipeline implementing parallel-by-locale processing was found'
    original_raw = RAW.read_bytes()
    errors = []
    try:
        for path, style in candidates:
            if PROCESSED.exists():
                shutil.rmtree(PROCESSED)
            if ROLLING.exists():
                ROLLING.unlink()
            suffix = secrets.token_hex(5)
            base = 1700000000 + secrets.randbelow(1000000)
            expected_es, expected_fr = write_dynamic_input(base, suffix)
            try:
                run = subprocess.run(
                    ['bash', '-x', str(path)], cwd=str(path.parent),
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=30, env={**os.environ, 'HOME': '/home/user'}
                )
                assert run.returncode == 0, f'exit status {run.returncode}'
                trace = run.stderr
                if style == 'parallel':
                    assert re.search(r'^\++ .*\bparallel\b', trace, re.MULTILINE), 'parallel was not executed'
                elif style == 'xargs':
                    assert re.search(r'^\++ .*\bxargs\b', trace, re.MULTILINE), 'parallel xargs was not executed'
                else:
                    assert re.search(r'^\++ .*\bwait\b', trace, re.MULTILINE), 'background jobs were not waited for'
                check_dynamic_outputs(expected_es, expected_fr)
                return
            except Exception as exc:
                errors.append(f'{path}: {exc}')
        raise AssertionError('No discovered Bash parallel pipeline processed derived input correctly. ' + '; '.join(errors))
    finally:
        RAW.write_bytes(original_raw)


check_original_outputs()
check_pipeline_execution()
print('verification passed')
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
