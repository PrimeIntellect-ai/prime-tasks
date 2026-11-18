#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/opt/cargo/bin:${PATH}"
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/cargo

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
from pathlib import Path

DB_PATH = Path('/home/user/source.db')
JSON_PATH = Path('/home/user/active_graph.json')
PROJECT_PATH = Path('/home/user/etl_project')


def check_indices():
    assert DB_PATH.is_file(), f'Database file not found at {DB_PATH}'
    with sqlite3.connect(DB_PATH) as conn:
        corrupt = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_corrupt_source'"
        ).fetchone()
        assert corrupt is None, "The index 'idx_corrupt_source' was not dropped from the database."

        optimized = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_events_optimized'"
        ).fetchone()
        assert optimized is not None, "The index 'idx_events_optimized' was not created in the database."

        rows = conn.execute("PRAGMA index_xinfo('idx_events_optimized')").fetchall()
        key_columns = [row[2] for row in rows if row[5] == 1 and row[2] is not None]
        assert key_columns[:4] == ['source_node', 'target_node', 'event_time', 'id'], (
            "idx_events_optimized must begin with source_node, target_node, event_time, id "
            f"to support the edge partition and latest-event ordering; got {key_columns}"
        )
        assert 'action' in key_columns[4:], (
            "idx_events_optimized must include action after the ordering columns so the analytical "
            "query is covered."
        )


def load_json():
    assert JSON_PATH.is_file(), f'Output JSON file not found at {JSON_PATH}'
    try:
        with JSON_PATH.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'The file {JSON_PATH} does not contain valid JSON: {exc}')


def expected_from_database():
    sql = """
        WITH ranked AS (
            SELECT source_node, target_node, action,
                   ROW_NUMBER() OVER (
                       PARTITION BY source_node, target_node
                       ORDER BY event_time DESC, id DESC
                   ) AS rn
            FROM events
        )
        SELECT source_node, target_node
        FROM ranked
        WHERE rn = 1 AND action = 'ADD'
        ORDER BY source_node, target_node
    """
    result = {}
    with sqlite3.connect(DB_PATH) as conn:
        for source, target in conn.execute(sql):
            result.setdefault(str(source), []).append(target)
    return result


def test_complete_etl_pipeline():
    # Preserve the original verifier's assertions against the seeded database/output.
    check_indices()
    assert load_json() == {'1': [2], '2': [4, 5]}, (
        'The initial active_graph.json does not match the seeded event log.'
    )

    manifest = PROJECT_PATH / 'Cargo.toml'
    src_dir = PROJECT_PATH / 'src'
    assert manifest.is_file(), f'Rust manifest not found at {manifest}'
    rust_files = list(src_dir.rglob('*.rs')) if src_dir.is_dir() else []
    assert rust_files, f'No Rust source files found under {src_dir}'

    manifest_text = manifest.read_text(errors='replace').lower()
    source_text = '\n'.join(path.read_text(errors='replace') for path in rust_files)
    lowered = source_text.lower()

    assert re.search(r'\brusqlite\b', manifest_text), 'Cargo.toml must depend on rusqlite.'
    assert re.search(r'\bserde_json\b', manifest_text), 'Cargo.toml must depend on serde_json.'
    assert 'rusqlite' in lowered, 'The Rust program must use rusqlite.'
    assert 'serde_json' in lowered, 'The Rust program must use serde_json.'

    assert re.search(r'row_number\s*\(\s*\)\s*over\s*\(', lowered, re.S), (
        'The analytical SQL must use ROW_NUMBER() as a window function.'
    )
    assert re.search(
        r'partition\s+by[\s\S]{0,200}source_node[\s\S]{0,120}target_node'
        r'[\s\S]{0,250}order\s+by[\s\S]{0,120}event_time\s+desc'
        r'[\s\S]{0,120}id\s+desc',
        lowered,
    ), 'The window must partition edges and order by event_time DESC, then id DESC.'

    placeholder = r'(?:\?[0-9]*|[:@$][a-z_][a-z0-9_]*)'
    assert re.search(r'limit\s+' + placeholder + r'\s+offset\s+' + placeholder, lowered), (
        'Pagination must use parameter placeholders for both LIMIT and OFFSET.'
    )
    page_size_patterns = [
        r'\b(?:page|batch|chunk|limit)[a-z0-9_]*\b\s*(?::[^=;]+)?=\s*50\b',
        r'params!\s*\[\s*50\b',
        r'\[\s*50\s*,',
    ]
    assert any(re.search(pattern, lowered) for pattern in page_size_patterns), (
        'The Rust implementation must bind or define an exact pagination size of 50 rows.'
    )
    assert re.search(r'\b(?:query|query_map|query_row|execute)\s*\(', lowered), (
        'The Rust program must execute the parameterized rusqlite query.'
    )

    build = subprocess.run(
        ['cargo', 'build', '--manifest-path', str(manifest)],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=240,
    )
    assert build.returncode == 0, f'Cargo compilation failed:\n{build.stdout}'

    # Add enough independently derived cases to require multiple 50-row pages, including
    # removals, re-additions, and equal timestamps where id must break the tie.
    with sqlite3.connect(DB_PATH) as conn:
        for i in range(137):
            source = 9001 + (i % 3)
            target = 20000 + (136 - i)
            stamp = f'2040-01-{(i % 9) + 1:02d} 12:00:00'
            conn.execute(
                'INSERT INTO events(source_node,target_node,event_time,action) VALUES(?,?,?,?)',
                (source, target, stamp, 'ADD'),
            )
            if i % 4 == 0:
                conn.execute(
                    'INSERT INTO events(source_node,target_node,event_time,action) VALUES(?,?,?,?)',
                    (source, target, stamp, 'REMOVE'),
                )
            if i % 7 == 0:
                conn.execute(
                    'INSERT INTO events(source_node,target_node,event_time,action) VALUES(?,?,?,?)',
                    (source, target, stamp, 'ADD'),
                )
        conn.commit()

    expected = expected_from_database()
    assert sum(len(v) for v in expected.values()) > 100, 'Dynamic fixture creation failed.'
    JSON_PATH.unlink(missing_ok=True)

    run = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(manifest)],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=240,
    )
    assert run.returncode == 0, f'Rust ETL execution failed:\n{run.stdout}'
    assert JSON_PATH.is_file(), 'The executed Rust program did not generate active_graph.json.'

    actual = load_json()
    assert actual == expected, (
        'The executed Rust ETL did not materialize the graph derived from the expanded database. '
        f'Expected {expected}, got {actual}'
    )
    assert all(isinstance(k, str) for k in actual), 'All JSON object keys must be strings.'
    for targets in actual.values():
        assert isinstance(targets, list), 'Each source node value must be an array.'
        assert all(isinstance(v, int) and not isinstance(v, bool) for v in targets), (
            'Target nodes must be integers.'
        )
        assert targets == sorted(targets), 'Every target-node array must be sorted ascending.'

    check_indices()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
