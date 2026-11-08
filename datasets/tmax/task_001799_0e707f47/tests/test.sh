#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import tokenize
import uuid

import pytest

HOME = '/home/user'
PIPELINE = f'{HOME}/pipeline.sh'
PROCESS = f'{HOME}/process.py'
OUTPUT = f'{HOME}/output'
DB = f'{HOME}/locales.db'


def remove_artifacts():
    os.makedirs(OUTPUT, exist_ok=True)
    for name in ('ja.html', 'de.html', 'ru.html', 'metadata.csv'):
        path = os.path.join(OUTPUT, name)
        if os.path.lexists(path):
            os.unlink(path)
    if os.path.lexists(DB):
        os.unlink(DB)


def expected_values(values):
    return {
        lang: (len(title), len(content))
        for lang, (title, content) in values.items()
    }


def assert_generated_outputs(template, values):
    lengths = expected_values(values)

    for lang, (title, content) in values.items():
        path = os.path.join(OUTPUT, f'{lang}.html')
        assert os.path.isfile(path), f'Output file {path} is missing'
        try:
            with open(path, 'r', encoding='utf-8') as f:
                actual = f.read()
        except UnicodeDecodeError:
            pytest.fail(f'{path} is not valid UTF-8')

        expected = template.replace('{{TITLE}}', title).replace('{{CONTENT}}', content)
        assert actual.lstrip('\ufeff') == expected, f'{path} was not generated from the template and source text'
        assert '{{TITLE}}' not in actual
        assert '{{CONTENT}}' not in actual

    csv_path = os.path.join(OUTPUT, 'metadata.csv')
    assert os.path.isfile(csv_path), 'metadata.csv is missing'
    with open(csv_path, 'r', encoding='utf-8-sig', newline='') as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ['lang', 'title_length', 'content_length']
    assert len(rows) == 4
    actual_rows = {row[0]: (int(row[1]), int(row[2])) for row in rows[1:]}
    assert actual_rows == lengths


def assert_dynamic_database(values):
    assert os.path.isfile(DB), f'Database {DB} is missing'
    lengths = expected_values(values)
    with sqlite3.connect(DB) as conn:
        schema = conn.execute('PRAGMA table_info(metadata)').fetchall()
        rows = conn.execute(
            'SELECT lang, title_length, content_length FROM metadata ORDER BY lang'
        ).fetchall()

    assert [(r[1], r[2].upper()) for r in schema] == [
        ('lang', 'TEXT'),
        ('title_length', 'INTEGER'),
        ('content_length', 'INTEGER'),
    ]
    expected = sorted((lang, lens[0], lens[1]) for lang, lens in lengths.items())
    assert rows == expected


def test_process_and_pipeline_behaviour():
    assert os.path.isfile(PROCESS), f'{PROCESS} does not exist'
    assert not os.path.islink(PROCESS), f'{PROCESS} must be a submitted Python script, not a symlink'
    assert os.path.isfile(PIPELINE), f'{PIPELINE} does not exist'
    assert os.access(PIPELINE, os.X_OK), f'{PIPELINE} is not executable'

    token = uuid.uuid4().hex[:10]
    values = {
        'ja': (f'東京{token}', f'猫世界{token}'),
        'de': (f'Äpfel{token}', f'Fußgänger{token}'),
        'ru': (f'Москва{token}', f'Тестовый{token}'),
    }
    encodings = {'ja': 'shift_jis', 'de': 'iso-8859-1', 'ru': 'koi8-r'}
    template = (
        f'<html data-verifier="{token}">\n'
        '<head><meta charset="UTF-8"></head>\n'
        '<body><h1>{{TITLE}}</h1><section>{{CONTENT}}</section></body>\n'
        '</html>'
    )

    source_paths = {lang: f'{HOME}/locales/{lang}.txt' for lang in values}
    saved_sources = {lang: open(path, 'rb').read() for lang, path in source_paths.items()}
    template_path = f'{HOME}/template.html'
    saved_template = open(template_path, 'rb').read()

    hidden_process = f'{HOME}/.process_verifier_{token}.py'
    process_mode = os.stat(PROCESS).st_mode
    sqlite_path = shutil.which('sqlite3')
    assert sqlite_path, 'sqlite3 command-line tool is unavailable'
    sqlite_backup = f'{sqlite_path}.verifier-{token}'
    event_log = f'/tmp/pipeline-events-{token}'
    sqlite_log = f'/tmp/sqlite-invocations-{token}'
    process_instrumented = False
    sqlite_instrumented = False
    baseline_result = None

    try:
        for lang, path in source_paths.items():
            title, content = values[lang]
            with open(path, 'w', encoding=encodings[lang], newline='') as f:
                f.write(title + '\n' + content)
        with open(template_path, 'w', encoding='utf-8', newline='') as f:
            f.write(template)

        # Exercise process.py directly on unpredictable encoded input. Prebuilt
        # fixed artifacts cannot satisfy this check because they are removed first.
        remove_artifacts()
        process_result = subprocess.run(
            ['python3', PROCESS], cwd=HOME, capture_output=True, text=True
        )
        assert process_result.returncode == 0, (
            f'process.py failed with code {process_result.returncode}: '
            f'{process_result.stderr}'
        )
        assert_generated_outputs(template, values)

        # Replace process.py temporarily with a transparent Python launcher that
        # records when pipeline.sh actually executes that exact path.
        os.rename(PROCESS, hidden_process)
        wrapper = f'''#!/usr/bin/python3
import tokenize
with open({event_log!r}, 'a', encoding='ascii') as _events:
    _events.write('P\\n')
with tokenize.open({hidden_process!r}) as _source_file:
    _source = _source_file.read()
exec(compile(_source, {PROCESS!r}, 'exec'), globals(), globals())
'''
        with open(PROCESS, 'w', encoding='utf-8') as f:
            f.write(wrapper)
        os.chmod(PROCESS, 0o755)
        process_instrumented = True

        # Interpose the real sqlite3 executable. The wrapper records both command
        # arguments and sqlite shell input, then delegates to the original binary.
        os.rename(sqlite_path, sqlite_backup)
        sqlite_wrapper = f'''#!/bin/bash
_tmp=$(mktemp)
cat > "$_tmp"
printf 'S\\n' >> {shlex.quote(event_log)}
{{
  printf '%s\\n' '--- sqlite3 invocation ---'
  printf 'ARG:%s\\n' "$@"
  printf '%s\\n' 'STDIN:'
  cat "$_tmp"
}} >> {shlex.quote(sqlite_log)}
{shlex.quote(sqlite_backup)} "$@" < "$_tmp"
_rc=$?
rm -f "$_tmp"
exit $_rc
'''
        with open(sqlite_path, 'w', encoding='utf-8') as f:
            f.write(sqlite_wrapper)
        os.chmod(sqlite_path, 0o755)
        sqlite_instrumented = True

        remove_artifacts()
        pipeline_result = subprocess.run(
            [PIPELINE], cwd=HOME, stdin=subprocess.DEVNULL,
            capture_output=True, text=True
        )
        assert pipeline_result.returncode == 0, (
            f'pipeline.sh failed with code {pipeline_result.returncode}: '
            f'{pipeline_result.stderr}'
        )

        with open(event_log, 'r', encoding='ascii') as f:
            events = [line.strip() for line in f if line.strip()]
        assert 'P' in events, 'pipeline.sh did not execute /home/user/process.py'
        assert 'S' in events, 'pipeline.sh did not execute the sqlite3 command-line tool'
        assert events[0] == 'P', 'pipeline.sh must execute process.py before invoking sqlite3'
        assert events.index('P') < events.index('S')

        with open(sqlite_log, 'r', encoding='utf-8', errors='replace') as f:
            sqlite_invocations = f.read()
        assert '.import' in sqlite_invocations, 'sqlite3 was not used for a bulk .import'
        assert 'metadata.csv' in sqlite_invocations, 'sqlite3 did not import metadata.csv'

        assert_generated_outputs(template, values)
        assert_dynamic_database(values)
    finally:
        if sqlite_instrumented:
            if os.path.lexists(sqlite_path):
                os.unlink(sqlite_path)
            os.rename(sqlite_backup, sqlite_path)
        if process_instrumented:
            if os.path.lexists(PROCESS):
                os.unlink(PROCESS)
            os.rename(hidden_process, PROCESS)
            os.chmod(PROCESS, process_mode)

        for lang, path in source_paths.items():
            with open(path, 'wb') as f:
                f.write(saved_sources[lang])
        with open(template_path, 'wb') as f:
            f.write(saved_template)

        for path in (event_log, sqlite_log):
            if os.path.lexists(path):
                os.unlink(path)

        # Restore the requested final state for the original fixed assertions.
        remove_artifacts()
        baseline_result = subprocess.run(
            [PIPELINE], cwd=HOME, stdin=subprocess.DEVNULL,
            capture_output=True, text=True
        )

    assert baseline_result.returncode == 0, (
        f'pipeline.sh failed on the original inputs: {baseline_result.stderr}'
    )


def test_pipeline_script_executable():
    pipeline_path = '/home/user/pipeline.sh'
    assert os.path.isfile(pipeline_path), f'{pipeline_path} does not exist'
    assert os.access(pipeline_path, os.X_OK), f'{pipeline_path} is not executable'


def test_html_outputs_exist_and_utf8():
    expected_files = {
        'ja.html': ('こんにちは', '世界'),
        'de.html': ('Grüße', 'Überraschung'),
        'ru.html': ('Привет', 'Мир')
    }

    for filename, (title, content) in expected_files.items():
        filepath = f'/home/user/output/{filename}'
        assert os.path.isfile(filepath), f'Output file {filepath} is missing'
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                html_content = f.read()
        except UnicodeDecodeError:
            pytest.fail(f'{filepath} is not valid UTF-8')

        assert title in html_content, f"{filepath} does not contain the expected title text '{title}'"
        assert content in html_content, f"{filepath} does not contain the expected content text '{content}'"
        assert '{{TITLE}}' not in html_content, f'{filepath} still contains {{{{TITLE}}}} placeholder'
        assert '{{CONTENT}}' not in html_content, f'{filepath} still contains {{{{CONTENT}}}} placeholder'


def test_database_contents():
    db_path = '/home/user/locales.db'
    assert os.path.isfile(db_path), f'Database {db_path} is missing'

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute('SELECT lang, title_length, content_length FROM metadata ORDER BY lang;')
        rows = cursor.fetchall()
        conn.close()
    except sqlite3.Error as e:
        pytest.fail(f'Failed to query database: {e}')

    expected_rows = [
        ('de', 5, 12),
        ('ja', 5, 2),
        ('ru', 6, 3)
    ]
    assert rows == expected_rows, f'Database contents do not match expected. Got: {rows}'


def test_cron_file():
    cron_path = '/home/user/locales_cron'
    assert os.path.isfile(cron_path), f'Crontab file {cron_path} is missing'

    with open(cron_path, 'r') as f:
        content = f.read().strip()

    pattern = r'^0\s+2\s+\*\s+\*\s+\*\s+/home/user/pipeline\.sh$'
    match = any(re.match(pattern, line.strip()) for line in content.splitlines() if line.strip())
    assert match, 'Crontab file does not contain the correct 2:00 AM schedule'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
