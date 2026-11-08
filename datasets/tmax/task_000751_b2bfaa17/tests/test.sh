#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH=/opt/rust/bin:$PATH
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/rust

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
from pathlib import Path

HOME = Path('/home/user')
PROJECT = HOME / 'vowel_embedder'
MANIFEST = PROJECT / 'Cargo.toml'
SCRIPT = HOME / 'run_pipeline.sh'
DATASET = HOME / 'dataset.csv'
DB = HOME / 'embeddings.db'
CLOSEST = HOME / 'closest.txt'
ISOLATED_TARGET = Path('/tmp/verifier_cargo_target')
ISOLATED_BINARY = ISOLATED_TARGET / 'release' / 'vowel_embedder'

EXPECTED_DATASET = {
    1: 'Hello world',
    2: 'The quick brown fox',
    3: 'Jumps over the lazy dog',
    42: 'Data science is fascinating because it allows us to uncover hidden patterns',
    73: 'Aaaa Eeee Iii Oooo Uuuu',
    88: 'Fascinating data patterns uncovered',
    99: 'Random text with no vowels rst lnm',
}


def run(command, *, cwd=HOME, env=None, timeout=600):
    return subprocess.run(
        command,
        cwd=str(cwd),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def embedding(text):
    lowered = text.lower()
    return tuple(lowered.count(v) for v in 'aeiou')


def expected_closest(rows, query_id):
    query = rows[query_id]
    choices = []
    for row_id, vector in rows.items():
        if row_id == query_id:
            continue
        distance = sum((x - y) ** 2 for x, y in zip(query, vector))
        choices.append((distance, row_id))
    return min(choices)[1]


def remove_database():
    for suffix in ('', '-wal', '-shm', '-journal'):
        try:
            Path(str(DB) + suffix).unlink()
        except FileNotFoundError:
            pass


def read_database():
    conn = sqlite3.connect(DB)
    try:
        cursor = conn.cursor()
        cursor.execute('SELECT id, a, e, i, o, u FROM embeddings ORDER BY id')
        return {row[0]: tuple(row[1:]) for row in cursor.fetchall()}
    finally:
        conn.close()


def test_run_pipeline_exists_and_executable():
    script_path = '/home/user/run_pipeline.sh'
    assert os.path.isfile(script_path), f'Script missing at {script_path}'

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Script {script_path} is not executable'
    assert MANIFEST.is_file(), f'Rust project missing Cargo.toml at {MANIFEST}'

    # Remove ordinary Cargo output so the pipeline must recreate a release build.
    run(['cargo', 'clean', '--manifest-path', str(MANIFEST)])
    result = run([str(SCRIPT)])
    built_binary = PROJECT / 'target' / 'release' / 'vowel_embedder'
    assert built_binary.is_file(), (
        'run_pipeline.sh did not create the release vowel_embedder binary; '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert os.access(built_binary, os.X_OK), 'Release vowel_embedder binary is not executable'


def test_closest_txt():
    output_path = '/home/user/closest.txt'
    assert os.path.isfile(output_path), f'Output file missing at {output_path}'

    with open(output_path, 'r') as f:
        content = f.read().strip()

    assert content == '73', f"Expected closest ID to be 73, but got '{content}'"


def test_sqlite_db():
    db_path = '/home/user/embeddings.db'
    assert os.path.isfile(db_path), f'Database file missing at {db_path}'

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='embeddings'")
    assert cursor.fetchone() is not None, "Table 'embeddings' does not exist in the database"

    cursor.execute('PRAGMA table_info(embeddings)')
    schema_rows = cursor.fetchall()
    columns = {row[1]: row[2].upper() for row in schema_rows}

    expected_columns = ['id', 'a', 'e', 'i', 'o', 'u']
    for col in expected_columns:
        assert col in columns, f"Column '{col}' missing in 'embeddings' table"
    assert [row[1] for row in schema_rows] == expected_columns, f'Unexpected embeddings schema: {schema_rows}'
    assert all(columns[col] == 'INTEGER' for col in expected_columns), f'Non-INTEGER schema: {schema_rows}'
    assert next(row for row in schema_rows if row[1] == 'id')[5] == 1, 'id is not the primary key'

    cursor.execute('SELECT a, e, i, o, u FROM embeddings WHERE id=42')
    row_42 = cursor.fetchone()
    assert row_42 is not None, "Row for ID 42 missing in 'embeddings' table"
    assert row_42 == (7, 7, 6, 4, 3), f'Expected embedding for ID 42 to be (7, 7, 6, 4, 3), got {row_42}'

    cursor.execute('SELECT a, e, i, o, u FROM embeddings WHERE id=73')
    row_73 = cursor.fetchone()
    assert row_73 is not None, "Row for ID 73 missing in 'embeddings' table"
    assert row_73 == (4, 4, 3, 4, 4), f'Expected embedding for ID 73 to be (4, 4, 3, 4, 4), got {row_73}'

    cursor.execute('SELECT id, a, e, i, o, u FROM embeddings ORDER BY id')
    actual = {row[0]: tuple(row[1:]) for row in cursor.fetchall()}
    expected = {row_id: embedding(text) for row_id, text in EXPECTED_DATASET.items()}
    assert actual == expected, f'Database does not contain exactly the embeddings for every dataset row: {actual}'
    conn.close()

    with DATASET.open(newline='') as f:
        source_rows = {int(row['id']): row['text'] for row in csv.DictReader(f)}
    assert source_rows == EXPECTED_DATASET, 'The supplied dataset.csv was modified'


def test_rust_project_exists():
    cargo_toml_path = '/home/user/vowel_embedder/Cargo.toml'
    assert os.path.isfile(cargo_toml_path), f'Rust project missing Cargo.toml at {cargo_toml_path}'


def test_compiled_program_on_unpredictable_dataset_and_queries():
    original_dataset = DATASET.read_bytes()
    shutil.rmtree(ISOLATED_TARGET, ignore_errors=True)

    # Build the submitted Rust target in a verifier-controlled, initially empty directory.
    env = os.environ.copy()
    env['CARGO_TARGET_DIR'] = str(ISOLATED_TARGET)
    run([
        'cargo', 'build', '--release', '--bin', 'vowel_embedder',
        '--manifest-path', str(MANIFEST),
    ], env=env)
    assert ISOLATED_BINARY.is_file() and os.access(ISOLATED_BINARY, os.X_OK), (
        'Cargo did not produce an executable vowel_embedder binary'
    )

    try:
        rng = secrets.SystemRandom()
        ids = rng.sample(range(1000, 1000000), 12)

        # The first three vectors force an equal-distance tie for ids[0].
        vectors = [
            (0, 0, 0, 0, 0),
            (1, 0, 0, 0, 0),
            (0, 1, 0, 0, 0),
        ]
        vectors.extend(tuple(rng.randrange(4, 13) for _ in range(5)) for _ in range(9))

        generated = {}
        vowel_chars = 'aeiou'
        for index, (row_id, vector) in enumerate(zip(ids, vectors)):
            chars = []
            for vowel_index, count in enumerate(vector):
                vowel = vowel_chars[vowel_index]
                chars.extend(vowel.upper() if n % 2 else vowel for n in range(count))
            chars.extend(list(' xyz, "!'))
            rng.shuffle(chars)
            generated[row_id] = ''.join(chars) + (' Z' * (index + 1))

        with DATASET.open('w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['id', 'text'])
            for row_id, text in generated.items():
                writer.writerow([row_id, text])

        expected_rows = {row_id: embedding(text) for row_id, text in generated.items()}
        remove_database()
        ingest = run([str(ISOLATED_BINARY)])
        assert DB.is_file(), f'Ingestion did not create {DB}; stderr={ingest.stderr!r}'
        assert read_database() == expected_rows, 'Ingestion did not correctly store every generated row'

        for query_id in ids:
            result = run([str(ISOLATED_BINARY), '--query', str(query_id)])
            assert re.fullmatch(r'[0-9]+\n?', result.stdout), (
                f'Query {query_id} printed content other than only an ID: {result.stdout!r}'
            )
            actual = int(result.stdout.strip())
            expected = expected_closest(expected_rows, query_id)
            assert actual == expected, (
                f'Query {query_id} returned {actual}, expected {expected}; '
                f'stderr={result.stderr!r}'
            )

        tie_expected = min(ids[1], ids[2])
        assert expected_closest(expected_rows, ids[0]) == tie_expected, 'Verifier tie fixture is invalid'
    finally:
        DATASET.write_bytes(original_dataset)
        remove_database()
        try:
            CLOSEST.unlink()
        except FileNotFoundError:
            pass
        run([str(SCRIPT)])

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
