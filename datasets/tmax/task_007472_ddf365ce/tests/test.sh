#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'RUN_EOF' > /tmp/run_submission.py
import csv
import os
import sqlite3
import subprocess
import sys
from pathlib import Path

workspace = Path('/home/user/loc_workspace')
updates = workspace / 'updates'

expected_new_strings = [
    {'en_source': 'Save changes.', 'es_target': 'Guardar cambios.', 'fr_target': 'Enregistrer les modifications.'},
    {'en_source': 'Cancel operation', 'es_target': 'Cancelar la operación', 'fr_target': "Annuler l'opération"},
    {'en_source': 'Welcome to the dashboard', 'es_target': 'Bienvenido al panel', 'fr_target': 'Bienvenue sur le tableau de bord'},
    {'en_source': 'Delete user accounts permanently', 'es_target': 'Eliminar cuentas de usuario permanentemente', 'fr_target': 'Supprimer les comptes'},
]
expected_logs = [
    {'date': '2023-10-01', 'translator_id': 'user1', 'word_count': '500'},
    {'date': '2023-10-02', 'translator_id': 'user1', 'word_count': '300'},
    {'date': '2023-10-04', 'translator_id': 'user1', 'word_count': '600'},
    {'date': '2023-10-01', 'translator_id': 'user2', 'word_count': '100'},
    {'date': '2023-10-03', 'translator_id': 'user2', 'word_count': '250'},
    {'date': '2023-10-04', 'translator_id': 'user2', 'word_count': '150'},
]

def read_csv(path):
    with path.open(newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))

assert updates.is_dir(), 'updates directory is missing'
assert (updates / 'new_strings.csv').is_file(), 'new_strings.csv was not extracted'
assert (updates / 'translation_logs.csv').is_file(), 'translation_logs.csv was not extracted'
assert read_csv(updates / 'new_strings.csv') == expected_new_strings, 'extracted new_strings.csv is not the downloaded input'
assert read_csv(updates / 'translation_logs.csv') == expected_logs, 'extracted translation_logs.csv is not the downloaded input'

scripts = sorted(p for p in workspace.rglob('*.py') if p.is_file())
assert scripts, 'No Python processing script was created in the workspace'

# Restore the specified starting database and remove generated products so that
# the submitted scripts, rather than pre-fabricated files, must recreate them.
db = workspace / 'translations.db'
if db.exists():
    db.unlink()
conn = sqlite3.connect(db)
conn.executescript('''
CREATE TABLE locales (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    en_source TEXT UNIQUE,
    es_target TEXT,
    fr_target TEXT
);
INSERT INTO locales (en_source, es_target, fr_target) VALUES ('Save changes', 'Guardar cambios', 'Enregistrer les modifications');
INSERT INTO locales (en_source, es_target, fr_target) VALUES ('Cancel operation', 'Cancelar', 'Annuler');
INSERT INTO locales (en_source, es_target, fr_target) VALUES ('Delete user account permanently', 'Eliminar cuenta de usuario permanentemente', 'Supprimer le compte');
''')
conn.commit()
conn.close()

for name in ('fuzzy_matches.csv', 'rolling_stats.csv', 'final_export.json'):
    path = workspace / name
    if path.exists():
        path.unlink()

for script in scripts:
    result = subprocess.run(
        [sys.executable, str(script)], cwd=str(workspace),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        timeout=60
    )
    assert result.returncode == 0, f'{script} failed when executed:\n{result.stdout}'

for name in ('fuzzy_matches.csv', 'rolling_stats.csv', 'final_export.json'):
    assert (workspace / name).is_file(), f'Submitted Python script(s) did not generate {name}'
RUN_EOF

if ! python3 /tmp/run_submission.py 2>&1; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import sqlite3
from collections import defaultdict
from datetime import datetime, timedelta
from difflib import SequenceMatcher

WORKSPACE = '/home/user/loc_workspace'
INITIAL_ROWS = [
    {'id': 1, 'en_source': 'Save changes', 'es_target': 'Guardar cambios', 'fr_target': 'Enregistrer les modifications'},
    {'id': 2, 'en_source': 'Cancel operation', 'es_target': 'Cancelar', 'fr_target': 'Annuler'},
    {'id': 3, 'en_source': 'Delete user account permanently', 'es_target': 'Eliminar cuenta de usuario permanentemente', 'fr_target': 'Supprimer le compte'},
]

def csv_rows(path):
    with open(path, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        return reader.fieldnames, list(reader)

def expected_processing():
    _, incoming = csv_rows(os.path.join(WORKSPACE, 'updates', 'new_strings.csv'))
    records = [dict(row) for row in INITIAL_ROWS]
    fuzzy = []
    next_id = 4
    for new in incoming:
        scored = [
            (SequenceMatcher(None, new['en_source'], old['en_source']).ratio(), old['en_source'])
            for old in records
        ]
        max_ratio = max(ratio for ratio, _ in scored)
        matched = min(text for ratio, text in scored if ratio == max_ratio)
        if 0.80 <= max_ratio < 1.0:
            fuzzy.append({
                'new_en_source': new['en_source'],
                'matched_db_en_source': matched,
                'similarity_ratio': round(max_ratio, 3),
            })
        elif max_ratio == 1.0:
            record = next(r for r in records if r['en_source'] == new['en_source'])
            record['es_target'] = new['es_target']
            record['fr_target'] = new['fr_target']
        else:
            records.append({
                'id': next_id,
                'en_source': new['en_source'],
                'es_target': new['es_target'],
                'fr_target': new['fr_target'],
            })
            next_id += 1
    return records, fuzzy

def expected_rolling():
    _, logs = csv_rows(os.path.join(WORKSPACE, 'updates', 'translation_logs.csv'))
    counts = defaultdict(dict)
    for row in logs:
        counts[row['translator_id']][datetime.strptime(row['date'], '%Y-%m-%d').date()] = int(row['word_count'])
    result = []
    for translator in sorted(counts):
        for day in sorted(counts[translator]):
            total = sum(counts[translator].get(day - timedelta(days=n), 0) for n in range(3))
            result.append({
                'date': day.isoformat(),
                'translator_id': translator,
                'rolling_3d_sum': str(total),
            })
    return result

def test_updates_extracted():
    updates_dir = "/home/user/loc_workspace/updates"
    assert os.path.isdir(updates_dir), f"Expected directory {updates_dir} to exist."
    new_strings_path = os.path.join(updates_dir, "new_strings.csv")
    assert os.path.isfile(new_strings_path), f"Expected file {new_strings_path} to exist."
    logs_path = os.path.join(updates_dir, "translation_logs.csv")
    assert os.path.isfile(logs_path), f"Expected file {logs_path} to exist."

def test_fuzzy_matches():
    fuzzy_path = "/home/user/loc_workspace/fuzzy_matches.csv"
    assert os.path.isfile(fuzzy_path), f"Expected file {fuzzy_path} to exist."
    with open(fuzzy_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['new_en_source', 'matched_db_en_source', 'similarity_ratio'], f"Incorrect headers in fuzzy_matches.csv: {reader.fieldnames}"
        rows = list(reader)
        assert len(rows) == 2, f"Expected exactly 2 fuzzy matches, got {len(rows)}."
        r1 = next((r for r in rows if r['new_en_source'] == 'Save changes.'), None)
        assert r1 is not None, "Missing fuzzy match for 'Save changes.'"
        assert r1['matched_db_en_source'] == 'Save changes', "Incorrect DB match for 'Save changes.'"
        assert float(r1['similarity_ratio']) == 0.96, f"Incorrect ratio for 'Save changes.': {r1['similarity_ratio']}"
        r2 = next((r for r in rows if r['new_en_source'] == 'Delete user accounts permanently'), None)
        assert r2 is not None, "Missing fuzzy match for 'Delete user accounts permanently'"
        assert r2['matched_db_en_source'] == 'Delete user account permanently', "Incorrect DB match for 'Delete user accounts permanently'"
        assert float(r2['similarity_ratio']) == 0.984, f"Incorrect ratio for 'Delete user accounts permanently': {r2['similarity_ratio']}"

    _, expected = expected_processing()
    actual = [{
        'new_en_source': r['new_en_source'],
        'matched_db_en_source': r['matched_db_en_source'],
        'similarity_ratio': float(r['similarity_ratio']),
    } for r in rows]
    assert actual == expected, f'fuzzy_matches.csv does not contain the complete expected result: {actual}'

def test_rolling_stats():
    stats_path = "/home/user/loc_workspace/rolling_stats.csv"
    assert os.path.isfile(stats_path), f"Expected file {stats_path} to exist."
    with open(stats_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['date', 'translator_id', 'rolling_3d_sum'], f"Incorrect headers in rolling_stats.csv: {reader.fieldnames}"
        rows = list(reader)
        assert len(rows) == 6, f"Expected exactly 6 rolling stat rows, got {len(rows)}."
        u2_10_03 = next((r for r in rows if r['translator_id'] == 'user2' and r['date'] == '2023-10-03'), None)
        assert u2_10_03 is not None, "Missing rolling stat for user2 on 2023-10-03"
        assert int(u2_10_03['rolling_3d_sum']) == 350, f"Incorrect rolling sum for user2 on 2023-10-03: {u2_10_03['rolling_3d_sum']} (expected 350)"
        u1_10_04 = next((r for r in rows if r['translator_id'] == 'user1' and r['date'] == '2023-10-04'), None)
        assert u1_10_04 is not None, "Missing rolling stat for user1 on 2023-10-04"
        assert int(u1_10_04['rolling_3d_sum']) == 900, f"Incorrect rolling sum for user1 on 2023-10-04: {u1_10_04['rolling_3d_sum']} (expected 900)"

    assert rows == expected_rolling(), 'rolling_stats.csv has incorrect calculations, missing dates, duplicates, or incorrect ordering'

def test_final_export_json():
    json_path = "/home/user/loc_workspace/final_export.json"
    assert os.path.isfile(json_path), f"Expected file {json_path} to exist."
    with open(json_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "final_export.json is not valid JSON."
        assert isinstance(data, list), "final_export.json must be a JSON array."
        assert len(data) == 4, f"Expected 4 rows in final DB export, got {len(data)}."
        cancel = next((r for r in data if r.get('en_source') == 'Cancel operation'), None)
        assert cancel is not None, "Missing 'Cancel operation' in final export."
        assert cancel.get('es_target') == 'Cancelar la operación', "Did not update exact match for 'Cancel operation'."
        welcome = next((r for r in data if r.get('en_source') == 'Welcome to the dashboard'), None)
        assert welcome is not None, "Missing 'Welcome to the dashboard' in final export (new string not inserted)."
        assert welcome.get('fr_target') == 'Bienvenue sur le tableau de bord', "Incorrect fr_target for new match."

    expected, _ = expected_processing()
    assert all(isinstance(r, dict) and set(r) == {'id', 'en_source', 'es_target', 'fr_target'} for r in data), 'Every exported object must contain exactly the database columns'
    assert sorted(data, key=lambda r: r['id']) == expected, 'final_export.json is not a complete and accurate export of locales'

def test_database_updated():
    db_path = "/home/user/loc_workspace/translations.db"
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT count(*) FROM locales;")
    count = cursor.fetchone()[0]
    assert count == 4, f"Expected 4 rows in locales table, found {count}."
    cursor.execute("SELECT es_target FROM locales WHERE en_source='Cancel operation';")
    result = cursor.fetchone()
    assert result is not None, "Row with en_source='Cancel operation' not found in DB."
    assert result[0] == 'Cancelar la operación', "Database was not updated for 'Cancel operation'."

    cursor.execute('SELECT id, en_source, es_target, fr_target FROM locales ORDER BY id')
    actual = [dict(zip(('id', 'en_source', 'es_target', 'fr_target'), row)) for row in cursor.fetchall()]
    expected, _ = expected_processing()
    assert actual == expected, f'locales table does not contain the complete expected final state: {actual}'
    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
