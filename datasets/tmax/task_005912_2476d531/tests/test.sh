#!/bin/bash
set -e
mkdir -p /logs/verifier

SQLITE_REAL=/tmp/verifier-sqlite3-real
SQLITE_LOG=/tmp/verifier-sqlite3.log
rm -f "$SQLITE_LOG" "$SQLITE_REAL"
mv /usr/bin/sqlite3 "$SQLITE_REAL"
cat > /usr/bin/sqlite3 <<'WRAPPER_EOF'
#!/bin/bash
REAL=/tmp/verifier-sqlite3-real
LOG=/tmp/verifier-sqlite3.log
INPUT=$(mktemp)
cat > "$INPUT"
{
  echo '=== sqlite3 invocation ==='
  printf 'ARG: %s\n' "$@"
  cat "$INPUT"
  for arg in "$@"; do
    if [ -f "$arg" ]; then
      echo "=== argument file: $arg ==="
      cat "$arg"
    fi
  done
} >> "$LOG"
"$REAL" "$@" < "$INPUT"
status=$?
rm -f "$INPUT"
exit $status
WRAPPER_EOF
chmod 755 /usr/bin/sqlite3
touch "$SQLITE_LOG"
chmod 666 "$SQLITE_LOG"

cleanup() {
  rm -f /usr/bin/sqlite3
  if [ -e "$SQLITE_REAL" ]; then
    mv "$SQLITE_REAL" /usr/bin/sqlite3
  fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import subprocess

import pytest

SOURCE = '/home/user/analyzer.c'
BINARY = '/home/user/analyzer'
OUTPUT = '/home/user/intra_institutional_citations.csv'
DATA = '/home/user/data'
SQLITE_LOG = '/tmp/verifier-sqlite3.log'
HEADER = ['author_id', 'author_name', 'citing_paper_id', 'cited_paper_id', 'institution_id']

ORIGINAL_AUTHORS = '''author_id,name,institution_id
1,Alice,INST_A
2,Bob,INST_B
3,Charlie,INST_A
4,David,INST_C
5,Eve,INST_B
6,Frank,INST_D
'''
ORIGINAL_PAPERS = [
    {'paper_id': 101, 'title': 'AI Systems', 'author_ids': [1, 2]},
    {'paper_id': 102, 'title': 'Data Mining', 'author_ids': [3]},
    {'paper_id': 103, 'title': 'Graph DBs', 'author_ids': [4, 5]},
    {'paper_id': 104, 'title': 'NLP Trends', 'author_ids': [6]},
    {'paper_id': 105, 'title': 'Quantum ML', 'author_ids': [2]},
]
ORIGINAL_CITATIONS = '''citing_paper_id,cited_paper_id
101,102
101,104
103,101
103,105
105,103
'''


def write_original_data():
    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, 'authors.csv'), 'w', encoding='utf-8', newline='') as f:
        f.write(ORIGINAL_AUTHORS)
    with open(os.path.join(DATA, 'papers.json'), 'w', encoding='utf-8') as f:
        json.dump(ORIGINAL_PAPERS, f)
    with open(os.path.join(DATA, 'citations.csv'), 'w', encoding='utf-8', newline='') as f:
        f.write(ORIGINAL_CITATIONS)


def run_analyzer():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run([BINARY], cwd='/home/user', text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert result.returncode == 0, (
        f'analyzer exited with {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


@pytest.fixture(scope='session', autouse=True)
def compile_and_run_original():
    assert os.path.isfile(SOURCE), 'The C source file /home/user/analyzer.c is missing.'
    assert os.path.getsize(SOURCE) > 0, 'The C source file is empty.'
    build = subprocess.run(['gcc', '-std=c11', '-O2', '-o', BINARY, SOURCE], text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert build.returncode == 0, f'Failed to compile analyzer.c:\n{build.stderr}'
    write_original_data()
    open(SQLITE_LOG, 'w').close()
    run_analyzer()


def test_c_source_exists():
    assert os.path.isfile('/home/user/analyzer.c'), 'The C source file /home/user/analyzer.c is missing.'


def test_output_csv_exists():
    assert os.path.isfile('/home/user/intra_institutional_citations.csv'), 'The output CSV file /home/user/intra_institutional_citations.csv is missing.'


def test_output_csv_content():
    expected_rows = [
        ['author_id', 'author_name', 'citing_paper_id', 'cited_paper_id', 'institution_id'],
        ['1', 'Alice', '101', '102', 'INST_A'],
        ['2', 'Bob', '105', '103', 'INST_B'],
        ['5', 'Eve', '103', '101', 'INST_B'],
        ['5', 'Eve', '103', '105', 'INST_B']
    ]

    with open('/home/user/intra_institutional_citations.csv', 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = [row for row in reader if row]

    assert actual_rows == expected_rows, f'The output CSV content does not match the expected output. Got: {actual_rows}'


def derive_expected(authors, papers, citations):
    author_by_id = {a['author_id']: a for a in authors}
    paper_authors = {p['paper_id']: p['author_ids'] for p in papers}
    rows = set()
    for citing, cited in citations:
        cited_institutions = {
            author_by_id[aid]['institution_id'] for aid in paper_authors[cited]
        }
        for aid in paper_authors[citing]:
            author = author_by_id[aid]
            if author['institution_id'] in cited_institutions:
                rows.add((aid, author['name'], citing, cited, author['institution_id']))
    return [HEADER] + [[str(v) for v in row] for row in sorted(rows, key=lambda r: (r[0], r[2], r[3]))]


def test_program_recomputes_randomized_data_and_uses_sqlite_json():
    rng = random.SystemRandom()
    base = rng.randrange(1000, 50000)
    author_ids = [base + x for x in (7, 19, 41, 68, 93, 127, 166)]
    paper_ids = [base * 10 + x for x in (3, 17, 44, 78, 119)]
    suffix = str(rng.randrange(100000, 999999))

    authors = [
        {'author_id': author_ids[0], 'name': 'Aster' + suffix, 'institution_id': 'LAB_X_' + suffix},
        {'author_id': author_ids[1], 'name': 'Birch' + suffix, 'institution_id': 'LAB_Y_' + suffix},
        {'author_id': author_ids[2], 'name': 'Cedar' + suffix, 'institution_id': 'LAB_X_' + suffix},
        {'author_id': author_ids[3], 'name': 'Dahlia' + suffix, 'institution_id': 'LAB_Z_' + suffix},
        {'author_id': author_ids[4], 'name': 'Elm' + suffix, 'institution_id': 'LAB_Y_' + suffix},
        {'author_id': author_ids[5], 'name': 'Fir' + suffix, 'institution_id': 'LAB_W_' + suffix},
        {'author_id': author_ids[6], 'name': 'Grove' + suffix, 'institution_id': 'LAB_X_' + suffix},
    ]
    papers = [
        {'paper_id': paper_ids[0], 'title': 'One ' + suffix, 'author_ids': [author_ids[0], author_ids[1]]},
        {'paper_id': paper_ids[1], 'title': 'Two ' + suffix, 'author_ids': [author_ids[2], author_ids[6]]},
        {'paper_id': paper_ids[2], 'title': 'Three ' + suffix, 'author_ids': [author_ids[3], author_ids[4]]},
        {'paper_id': paper_ids[3], 'title': 'Four ' + suffix, 'author_ids': [author_ids[5]]},
        {'paper_id': paper_ids[4], 'title': 'Five ' + suffix, 'author_ids': [author_ids[1]]},
    ]
    citations = [
        (paper_ids[0], paper_ids[1]),
        (paper_ids[0], paper_ids[3]),
        (paper_ids[2], paper_ids[0]),
        (paper_ids[2], paper_ids[4]),
        (paper_ids[4], paper_ids[2]),
    ]

    with open(os.path.join(DATA, 'authors.csv'), 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['author_id', 'name', 'institution_id'])
        for a in authors:
            writer.writerow([a['author_id'], a['name'], a['institution_id']])
    with open(os.path.join(DATA, 'papers.json'), 'w', encoding='utf-8') as f:
        json.dump(papers, f)
    with open(os.path.join(DATA, 'citations.csv'), 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['citing_paper_id', 'cited_paper_id'])
        writer.writerows(citations)

    open(SQLITE_LOG, 'w').close()
    run_analyzer()

    assert os.path.isfile(OUTPUT), 'The analyzer did not generate the output CSV.'
    with open(OUTPUT, 'r', encoding='utf-8', newline='') as f:
        actual = list(csv.reader(f))
    expected = derive_expected(authors, papers, citations)
    assert actual == expected, f'Analyzer failed on verifier-generated input. Expected {expected}, got {actual}'
    assert len(actual[1:]) == len({tuple(row) for row in actual[1:]}), 'Output contains duplicate rows.'

    with open(SQLITE_LOG, 'r', encoding='utf-8', errors='replace') as f:
        sqlite_activity = f.read()
    assert '=== sqlite3 invocation ===' in sqlite_activity, 'The C program did not execute the sqlite3 command-line tool.'
    assert re.search(r'json_each\s*\(', sqlite_activity, re.IGNORECASE), (
        'The SQL executed by the program did not use SQLite json_each to map papers.json author arrays.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
