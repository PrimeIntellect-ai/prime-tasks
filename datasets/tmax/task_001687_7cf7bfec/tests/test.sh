#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import sqlite3
import subprocess
import uuid
from pathlib import Path


def test_cleaned_data_csv():
    csv_path = "/home/user/cleaned_data.csv"
    assert os.path.isfile(csv_path), f"File not found: {csv_path}"

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['date', 'entity_id', 'non_ascii_count', 'rolling_avg_score'], f"Incorrect header in {csv_path}"

        rows = list(reader)
        expected_rows = [
            ['2023-10-01', 'A', '1', '10.0'],
            ['2023-10-02', 'A', '1', '12.5'],
            ['2023-10-03', 'A', '6', '15.0'],
            ['2023-10-04', 'A', '1', '15.0'],
            ['2023-10-01', 'B', '0', '5.0'],
            ['2023-10-02', 'B', '0', '5.0'],
            ['2023-10-03', 'B', '0', '7.0']
        ]

        rows_sorted = sorted(rows, key=lambda x: (x[1], x[0]))
        expected_sorted = sorted(expected_rows, key=lambda x: (x[1], x[0]))

        assert len(rows_sorted) == len(expected_sorted), f"Expected {len(expected_sorted)} rows, got {len(rows_sorted)}"

        for r, e in zip(rows_sorted, expected_sorted):
            assert r[0] == e[0], f"Date mismatch: expected {e[0]}, got {r[0]}"
            assert r[1] == e[1], f"Entity mismatch: expected {e[1]}, got {r[1]}"
            assert r[2] == e[2], f"Non-ASCII count mismatch: expected {e[2]}, got {r[2]}"
            assert abs(float(r[3]) - float(e[3])) <= 0.01, f"Rolling avg mismatch: expected {e[3]}, got {r[3]}"


def test_sqlite_database():
    db_path = "/home/user/metrics.db"
    assert os.path.isfile(db_path), f"Database file not found: {db_path}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='entity_metrics'")
    assert cursor.fetchone() is not None, "Table 'entity_metrics' not found in database"

    cursor.execute("SELECT date, entity_id, non_ascii_count, rolling_avg_score FROM entity_metrics ORDER BY entity_id, date")
    rows = cursor.fetchall()

    expected = [
        ('2023-10-01', 'A', 1, 10.0),
        ('2023-10-02', 'A', 1, 12.5),
        ('2023-10-03', 'A', 6, 15.0),
        ('2023-10-04', 'A', 1, 15.0),
        ('2023-10-01', 'B', 0, 5.0),
        ('2023-10-02', 'B', 0, 5.0),
        ('2023-10-03', 'B', 0, 7.0)
    ]

    assert len(rows) == len(expected), f"Row count mismatch in DB. Expected {len(expected)}, got {len(rows)}"

    for r, e in zip(rows, expected):
        assert r[0] == e[0], f"Date mismatch in DB: expected {e[0]}, got {r[0]}"
        assert r[1] == e[1], f"Entity mismatch in DB: expected {e[1]}, got {r[1]}"
        assert int(r[2]) == e[2], f"Non-ASCII count mismatch in DB: expected {e[2]}, got {r[2]}"
        assert abs(float(r[3]) - e[3]) <= 0.01, f"Rolling avg mismatch in DB: expected {e[3]}, got {r[3]}"

    conn.close()


def _remove_outputs():
    for path in [
        "/home/user/cleaned_data.csv",
        "/home/user/metrics.db",
        "/home/user/metrics.db-wal",
        "/home/user/metrics.db-shm",
    ]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def _validate_generated_outputs(expected):
    csv_path = "/home/user/cleaned_data.csv"
    db_path = "/home/user/metrics.db"
    assert os.path.isfile(csv_path)
    assert os.path.isfile(db_path)

    with open(csv_path, newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)
    assert header == ['date', 'entity_id', 'non_ascii_count', 'rolling_avg_score']
    assert len(rows) == len(expected)
    rows = sorted(rows, key=lambda r: (r[1], r[0]))
    for actual, wanted in zip(rows, expected):
        assert len(actual) == 4
        assert actual[0] == wanted[0]
        assert actual[1] == wanted[1]
        assert actual[2] == str(wanted[2])
        assert abs(float(actual[3]) - wanted[3]) <= 0.01

    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='entity_metrics'")
        assert cur.fetchone() is not None
        cur.execute("SELECT date, entity_id, non_ascii_count, rolling_avg_score FROM entity_metrics ORDER BY entity_id, date")
        db_rows = cur.fetchall()
        assert len(db_rows) == len(expected)
        for actual, wanted in zip(db_rows, expected):
            assert actual[0] == wanted[0]
            assert actual[1] == wanted[1]
            assert int(actual[2]) == wanted[2]
            assert abs(float(actual[3]) - wanted[3]) <= 0.01
    finally:
        conn.close()


def test_script_recomputes_from_raw_data():
    home = Path('/home/user')
    scripts = [p for p in home.rglob('*.py') if p.is_file() and not any(part.startswith('.') for part in p.relative_to(home).parts)]
    scripts.sort(key=lambda p: (p.name != 'process.py', str(p)))
    assert scripts, "No Python transformation script was found under /home/user"

    rng = random.SystemRandom()
    token = uuid.uuid4().hex[:10]
    entities = [f"entity_{token}_{i}" for i in range(3)]
    text_bases = ["plain ASCII", "Café😊", "東京語", "Привет!", "naïve🧪"]
    records = []
    for entity_index, entity in enumerate(entities):
        for day in range(1, 6):
            text = text_bases[(entity_index + day) % len(text_bases)] + str(rng.randrange(10000, 99999))
            score = float(rng.randrange(-40, 121))
            records.append({
                'date': f'2025-07-{day:02d}',
                'entity_id': entity,
                'text': text,
                'daily_score': score,
            })
    rng.shuffle(records)

    expected = []
    for entity in entities:
        group = sorted((r for r in records if r['entity_id'] == entity), key=lambda r: r['date'])
        scores = []
        for row in group:
            scores.append(row['daily_score'])
            rolling = round(sum(scores[-3:]) / len(scores[-3:]), 2)
            expected.append((row['date'], entity, sum(ord(ch) > 127 for ch in row['text']), rolling))
    expected.sort(key=lambda r: (r[1], r[0]))

    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=['date', 'entity_id', 'text', 'daily_score'], lineterminator='\n')
    writer.writeheader()
    writer.writerows(records)
    generated_raw = stream.getvalue().encode('utf-8')

    managed = [home / 'raw_data.csv', home / 'cleaned_data.csv', home / 'metrics.db']
    backups = {p: p.read_bytes() if p.exists() else None for p in managed}
    errors = []
    passed = False
    try:
        for script in scripts:
            (home / 'raw_data.csv').write_bytes(generated_raw)
            _remove_outputs()
            try:
                subprocess.run(
                    ['python3', str(script)],
                    cwd=str(home),
                    check=True,
                    timeout=30,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                _validate_generated_outputs(expected)
                passed = True
                break
            except Exception as exc:
                errors.append(f"{script}: {exc}")
        assert passed, "No submitted Python script correctly regenerated both artifacts from changed raw input. " + "; ".join(errors)
    finally:
        _remove_outputs()
        for path, data in backups.items():
            if data is None:
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
            else:
                path.write_bytes(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
