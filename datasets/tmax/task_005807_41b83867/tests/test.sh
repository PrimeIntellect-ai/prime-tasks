#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import shlex
import secrets
import random
import sqlite3
import subprocess
from pathlib import Path

SCRIPT_PATH = Path('/home/user/analyze.sh')
OUTPUT_PATH = Path('/home/user/top_papers.txt')
DB_PATH = Path('/home/user/research_data.db')
SQLITE_PATH = Path('/usr/bin/sqlite3')

EXPECTED_OUTPUT = '''Alice|Beta|7
Carol|Eta|6
Carol|Zeta|6
Bob|Epsilon|5
David|Theta|1
'''


def run_submission(timeout=15):
    capture = Path('/tmp/sqlite_capture_' + secrets.token_hex(8))
    real_sqlite = Path('/usr/bin/sqlite3.verifier-real')

    assert SQLITE_PATH.exists(), 'sqlite3 executable is missing.'
    assert not real_sqlite.exists(), 'Temporary sqlite3 verifier path already exists.'

    SQLITE_PATH.rename(real_sqlite)
    wrapper = f'''#!/bin/bash
{{
  printf 'ARG:%s\\n' "$@"
  printf '%s\\n' '---STDIN---'
}} >> {shlex.quote(str(capture))}
tee -a {shlex.quote(str(capture))} | {shlex.quote(str(real_sqlite))} "$@"
'''
    SQLITE_PATH.write_text(wrapper)
    SQLITE_PATH.chmod(0o755)

    try:
        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()
        result = subprocess.run(
            [str(SCRIPT_PATH)],
            cwd='/home/user',
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            env={**os.environ, 'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'},
        )
        captured_sql = capture.read_text(errors='replace') if capture.exists() else ''
        return result, captured_sql
    finally:
        if SQLITE_PATH.exists():
            SQLITE_PATH.unlink()
        real_sqlite.rename(SQLITE_PATH)
        if capture.exists():
            capture.unlink()


def test_script_exists_and_executable():
    """Test if the analyze.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f'Script {SCRIPT_PATH} is not executable.'


def test_execute_script_on_original_database():
    result, sql_text = run_submission()
    assert result.returncode == 0, f'analyze.sh failed:\n{result.stderr}'
    assert sql_text, 'analyze.sh did not invoke the sqlite3 command-line tool.'


def test_output_file_exists():
    """Test if the top_papers.txt output file exists."""
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} does not exist.'


def test_output_contents():
    """Test if the contents of top_papers.txt exactly match the expected output."""
    with open(OUTPUT_PATH, 'r') as f:
        content = f.read().strip()
    expected_stripped = EXPECTED_OUTPUT.strip()
    assert content == expected_stripped, \
        f'Output file contents do not match expected.\nExpected:\n{expected_stripped}\nGot:\n{content}'


def test_script_queries_dynamic_database_with_window_ranking():
    original_db = DB_PATH.read_bytes()
    rng = random.SystemRandom()
    token = secrets.token_hex(5)
    expected_rows = []

    try:
        for suffix in ('-wal', '-shm', '-journal'):
            p = Path(str(DB_PATH) + suffix)
            if p.exists():
                p.unlink()
        DB_PATH.unlink()

        con = sqlite3.connect(DB_PATH)
        try:
            con.executescript('''
                CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER, author_id INTEGER);
                CREATE TABLE citations (paper_id INTEGER, cited_by_paper_id INTEGER);
            ''')
            paper_id = 1
            citation_id = 100000
            for author_id in range(1, 17):
                author_name = f'Researcher_{token}_{author_id:02d}'
                con.execute('INSERT INTO authors VALUES (?, ?)', (author_id, author_name))

                top_count = rng.randint(5, 30)
                counts = [top_count, top_count if author_id % 4 == 0 else rng.randint(0, top_count - 1), rng.randint(0, top_count - 1)]
                titles = [f'{token}_Paper_{author_id:02d}_{letter}' for letter in ('A', 'B', 'C')]

                for title, count, year in zip(titles, counts, (2011, 2017, 2024)):
                    con.execute('INSERT INTO papers VALUES (?, ?, ?, ?)', (paper_id, title, year, author_id))
                    for _ in range(count):
                        con.execute('INSERT INTO citations VALUES (?, ?)', (paper_id, citation_id))
                        citation_id += 1
                    paper_id += 1

                old_title = f'{token}_Old_{author_id:02d}'
                con.execute('INSERT INTO papers VALUES (?, ?, 2010, ?)', (paper_id, old_title, author_id))
                for _ in range(top_count + 40):
                    con.execute('INSERT INTO citations VALUES (?, ?)', (paper_id, citation_id))
                    citation_id += 1
                paper_id += 1

                for title, count in zip(titles, counts):
                    if count == max(counts):
                        expected_rows.append((author_name, title, count))
            con.commit()
        finally:
            con.close()
        os.chmod(DB_PATH, 0o777)

        expected_rows.sort(key=lambda row: (-row[2], row[1]))
        expected = '\n'.join(f'{author}|{title}|{count}' for author, title, count in expected_rows[:10])

        result, sql_text = run_submission()
        assert result.returncode == 0, f'analyze.sh failed on the dynamic database:\n{result.stderr}'
        assert OUTPUT_PATH.is_file(), 'analyze.sh did not create top_papers.txt.'
        actual = OUTPUT_PATH.read_text().strip()
        assert actual == expected, f'Dynamic database output mismatch.\nExpected:\n{expected}\nGot:\n{actual}'

        sql_without_comments = re.sub(r'/\*.*?\*/', ' ', sql_text, flags=re.S)
        sql_without_comments = re.sub(r'--[^\n]*', ' ', sql_without_comments)
        assert re.search(r'\b(?:dense_rank|rank)\s*\(\s*\)\s*over\b', sql_without_comments, flags=re.I), \
            'The SQL executed through sqlite3 does not use RANK() or DENSE_RANK() as a window function.'
    finally:
        for suffix in ('-wal', '-shm', '-journal'):
            p = Path(str(DB_PATH) + suffix)
            if p.exists():
                p.unlink()
        DB_PATH.write_bytes(original_db)
        os.chmod(DB_PATH, 0o777)
        try:
            run_submission()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
