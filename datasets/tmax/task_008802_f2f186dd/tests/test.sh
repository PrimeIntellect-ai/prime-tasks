#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import sqlite3
import subprocess
import tempfile

DB_PATH = '/home/user/dataset.db'
SOURCE_PATH = '/home/user/metrics.cpp'
OUTPUT_PATH = '/home/user/top_coauthor_metrics.txt'
EXECUTABLE_PATH = '/tmp/submission_metrics'


def compute_expected_metrics(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    c.execute('SELECT id, name FROM authors')
    authors = c.fetchall()
    c.execute('SELECT author_id, paper_id FROM author_paper')
    author_paper = c.fetchall()
    c.execute('SELECT cited_paper_id, count FROM citations')
    citations = dict(c.fetchall())
    conn.close()

    author_papers_dict = {}
    paper_authors_dict = {}
    for aid, pid in author_paper:
        author_papers_dict.setdefault(aid, set()).add(pid)
        paper_authors_dict.setdefault(pid, set()).add(aid)

    results = []
    for aid, name in authors:
        coauthors = set()
        for pid in author_papers_dict.get(aid, set()):
            for co_aid in paper_authors_dict.get(pid, set()):
                if co_aid != aid:
                    coauthors.add(co_aid)

        coauthor_papers = set()
        for co_aid in coauthors:
            coauthor_papers.update(author_papers_dict.get(co_aid, set()))

        total_citations = sum(citations.get(pid, 0) for pid in coauthor_papers)
        results.append((name, len(coauthors), total_citations))

    results.sort(key=lambda x: (-x[2], x[0]))
    return results[:10]


def file_hash(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(65536), b''):
            h.update(chunk)
    return h.hexdigest()


def parse_output():
    assert os.path.isfile(OUTPUT_PATH), f'The program did not create {OUTPUT_PATH}.'
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()

    assert lines, 'The output file is empty.'
    assert all(line.strip() for line in lines), 'The output contains an empty line.'

    parsed_results = []
    for i, line in enumerate(lines):
        assert line == line.strip(), f'Line {i + 1} contains leading or trailing whitespace.'
        parts = line.split('|')
        assert len(parts) == 3, f"Line {i + 1} does not have exactly 3 parts separated by '|': {line}"
        try:
            coauthors = int(parts[1])
            citations = int(parts[2])
        except ValueError:
            raise AssertionError(f'Non-integer value found in metrics on line {i + 1}: {line}')
        parsed_results.append((parts[0], coauthors, citations))
    return parsed_results


def run_and_check(label):
    expected = compute_expected_metrics(DB_PATH)
    before_hash = file_hash(DB_PATH)
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    completed = subprocess.run(
        [EXECUTABLE_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f'Compiled program failed for {label} with exit code {completed.returncode}. '
        f'stdout: {completed.stdout} stderr: {completed.stderr}'
    )
    assert file_hash(DB_PATH) == before_hash, 'The program modified the database.'

    actual = parse_output()
    assert actual == expected, (
        f'The output metrics for {label} do not exactly match all expected top-10 rows. '
        f'Got {actual}, expected {expected}'
    )


def create_generated_database(path):
    conn = sqlite3.connect(path)
    c = conn.cursor()
    c.execute('CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT)')
    c.execute('CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT)')
    c.execute('CREATE TABLE author_paper (author_id INTEGER, paper_id INTEGER)')
    c.execute('CREATE TABLE citations (cited_paper_id INTEGER, count INTEGER)')

    names = ['Zara', 'Amy', 'Nora', 'Ben', 'Mira', 'Carl', 'Yuki', 'Dora',
             'Omar', 'Faye', 'Liam', 'Gina', 'Theo', 'Ivy']
    c.executemany('INSERT INTO authors VALUES (?, ?)',
                  [(i + 1, name) for i, name in enumerate(names)])

    papers = []
    links = []
    citation_rows = []

    # A chain of collaborations gives different authors overlapping coauthor papers.
    for i in range(1, 14):
        pid = i
        papers.append((pid, f'Collaboration {i}'))
        links.extend([(i, pid), (i + 1, pid)])
        citation_rows.append((pid, (i * 7) % 31 + 1))

    # Every author also has a solo paper whose citations count for their coauthors.
    for i in range(1, 15):
        pid = 100 + i
        papers.append((pid, f'Solo {i}'))
        links.append((i, pid))
        citation_rows.append((pid, i * 11))

    # A three-author paper checks unique coauthors and prevents double-counting a
    # paper that is written by more than one of the original author's coauthors.
    papers.append((300, 'Three Author Paper'))
    links.extend([(1, 300), (2, 300), (3, 300)])
    citation_rows.append((300, 47))

    c.executemany('INSERT INTO papers VALUES (?, ?)', papers)
    c.executemany('INSERT INTO author_paper VALUES (?, ?)', links)
    c.executemany('INSERT INTO citations VALUES (?, ?)', citation_rows)
    conn.commit()
    conn.close()


def test_compiles_runs_and_produces_exact_metrics():
    assert os.path.isfile(SOURCE_PATH), f'The source file was not found at {SOURCE_PATH}.'
    assert os.path.isfile(DB_PATH), f'The database file was not found at {DB_PATH}.'

    if os.path.exists(EXECUTABLE_PATH):
        os.remove(EXECUTABLE_PATH)
    compiled = subprocess.run(
        ['g++', '-std=c++17', SOURCE_PATH, '-lsqlite3', '-o', EXECUTABLE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f'metrics.cpp did not compile: {compiled.stderr}'
    assert os.path.isfile(EXECUTABLE_PATH) and os.access(EXECUTABLE_PATH, os.X_OK)

    backup_fd, backup_path = tempfile.mkstemp(prefix='dataset_backup_', suffix='.db')
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)

    generated_fd, generated_path = tempfile.mkstemp(prefix='generated_dataset_', suffix='.db')
    os.close(generated_fd)
    os.remove(generated_path)

    try:
        # Validate the required output on the supplied database, including Eve and
        # rejecting omitted or additional rows.
        run_and_check('the supplied database')

        # Re-run the submitted artifact on verifier-generated data so a manually
        # written answer or hard-coded five-row program cannot pass.
        create_generated_database(generated_path)
        shutil.copy2(generated_path, DB_PATH)
        run_and_check('the verifier-generated database')
    finally:
        shutil.copy2(backup_path, DB_PATH)
        if os.path.exists(backup_path):
            os.remove(backup_path)
        if os.path.exists(generated_path):
            os.remove(generated_path)

    # Leave the requested final output corresponding to the restored supplied DB.
    run_and_check('the restored supplied database')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
