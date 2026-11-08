#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import re
import secrets
import sqlite3
import string
import subprocess

SCRIPT = '/home/user/analyze.py'
CSV_PATH = '/home/user/top_growth.csv'
DB_PATH = '/home/user/research_data.db'
HEADERS = ['climate_zone', 'species', 'date', 'daily_growth', 'rolling_health']

BASELINE_EXPECTED = [
    {'climate_zone': 'Temperate', 'species': 'Pine', 'date': '2023-01-02', 'daily_growth': 5, 'rolling_health': 5.5},
    {'climate_zone': 'Temperate', 'species': 'Oak', 'date': '2023-01-03', 'daily_growth': 3, 'rolling_health': 9.0},
    {'climate_zone': 'Tropical', 'species': 'Palm', 'date': '2023-01-03', 'daily_growth': 6, 'rolling_health': 9.0},
    {'climate_zone': 'Tropical', 'species': 'Palm', 'date': '2023-01-02', 'daily_growth': 4, 'rolling_health': 9.5},
]


def extract_report_query():
    assert os.path.isfile(SCRIPT), f'Python script missing at {SCRIPT}'
    with open(SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    values = {}

    def resolve(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name) and node.id in values:
            return values[node.id]
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left, right = resolve(node.left), resolve(node.right)
            if left is not None and right is not None:
                return left + right
        if isinstance(node, ast.JoinedStr):
            parts = []
            for part in node.values:
                if not isinstance(part, ast.Constant) or not isinstance(part.value, str):
                    return None
                parts.append(part.value)
            return ''.join(parts)
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr in {'strip', 'lstrip', 'rstrip'} and not node.args):
            value = resolve(node.func.value)
            if value is not None:
                return getattr(value, node.func.attr)()
        return None

    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            value = resolve(node.value)
            if value is not None:
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        values[target.id] = value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            value = resolve(node.value)
            if value is not None:
                values[node.target.id] = value

    execute_calls = []
    forbidden_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr == 'execute':
            execute_calls.append(node)
        elif node.func.attr in {'executemany', 'executescript'}:
            forbidden_calls.append(node)

    assert not forbidden_calls, 'The report must be produced by one SQL query, not executemany/executescript'
    assert len(execute_calls) == 1, f'Expected exactly one SQL execute call, found {len(execute_calls)}'
    call = execute_calls[0]
    assert call.args, 'SQL execute call has no query argument'
    query = resolve(call.args[0])
    assert query is not None, 'The SQL passed to execute must be present as a string in analyze.py'

    upper = query.upper()
    assert re.search(r'\bWITH\b', upper), 'The report SQL must use a CTE'
    assert len(re.findall(r'\bJOIN\b', upper)) >= 2, 'The report SQL must perform the required table joins'
    assert re.search(r'\bLAG\s*\([^)]*\)\s*OVER\s*\(', upper, re.S), 'daily_growth must use SQL LAG() OVER()'
    assert re.search(r'\bAVG\s*\([^)]*\)\s*OVER\s*\(', upper, re.S), 'rolling_health must use SQL AVG() OVER()'
    assert re.search(r'\b(?:ROW_NUMBER|RANK|DENSE_RANK)\s*\(\s*\)\s*OVER\s*\(', upper, re.S), 'Top events must be ranked with a SQL window function'
    return query


def run_script():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        ['python3', SCRIPT], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f'analyze.py failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    assert os.path.isfile(CSV_PATH), f'Output CSV missing at {CSV_PATH}'


def read_csv_rows():
    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        assert reader.fieldnames == HEADERS, f'Expected headers {HEADERS}, got {reader.fieldnames}'
    return rows


def assert_report(rows, expected, source_name):
    assert len(rows) == len(expected), f'{source_name}: expected {len(expected)} rows, got {len(rows)}'

    def convert(row):
        assert set(row.keys()) == set(HEADERS), f'{source_name}: incorrect report columns'
        try:
            growth = int(row['daily_growth'])
        except (TypeError, ValueError):
            raise AssertionError(f"{source_name}: daily_growth {row['daily_growth']!r} is not an integer")
        try:
            health = float(row['rolling_health'])
        except (TypeError, ValueError):
            raise AssertionError(f"{source_name}: rolling_health {row['rolling_health']!r} is not a float")
        key = (str(row['climate_zone']), str(row['species']), str(row['date']))
        return key, growth, health

    actual_by_key = {}
    for row in rows:
        key, growth, health = convert(row)
        assert key not in actual_by_key, f'{source_name}: duplicate report event {key}'
        actual_by_key[key] = (growth, health)

    expected_by_key = {
        (r['climate_zone'], r['species'], r['date']): (r['daily_growth'], r['rolling_health'])
        for r in expected
    }
    assert set(actual_by_key) == set(expected_by_key), (
        f'{source_name}: wrong report events; expected {set(expected_by_key)}, got {set(actual_by_key)}'
    )
    for key, (expected_growth, expected_health) in expected_by_key.items():
        actual_growth, actual_health = actual_by_key[key]
        assert actual_growth == expected_growth, f'{source_name}: {key} has wrong daily_growth'
        raw_ok = math.isclose(actual_health, expected_health, rel_tol=0, abs_tol=1e-9)
        rounded_ok = math.isclose(actual_health, round(expected_health, 2), rel_tol=0, abs_tol=1e-9)
        assert raw_ok or rounded_ok, f'{source_name}: {key} has wrong rolling_health'


def run_query_directly(query):
    con = sqlite3.connect(DB_PATH)
    try:
        cur = con.execute(query)
        assert cur.description is not None, 'The submitted SQL did not return a result set'
        columns = [item[0] for item in cur.description]
        assert columns == HEADERS, f'The report SQL must return columns {HEADERS}, got {columns}'
        return [dict(zip(columns, row)) for row in cur.fetchall()]
    finally:
        con.close()


def derive_expected_from_database():
    con = sqlite3.connect(DB_PATH)
    try:
        records = con.execute('''
            SELECT m.measurement_id, m.plant_id, m.date, m.height_cm, m.health_score,
                   p.species, r.climate_zone
            FROM measurements AS m
            JOIN plants AS p ON p.plant_id = m.plant_id
            JOIN regions AS r ON r.region_id = p.region_id
        ''').fetchall()
    finally:
        con.close()

    by_plant = {}
    for record in records:
        by_plant.setdefault(record[1], []).append(record)

    events = []
    for measurements in by_plant.values():
        measurements.sort(key=lambda r: (r[2], r[0]))
        for index, record in enumerate(measurements):
            if index == 0 or record[3] is None or measurements[index - 1][3] is None:
                continue
            window = [r[4] for r in measurements[max(0, index - 2):index + 1] if r[4] is not None]
            health = sum(window) / len(window) if window else None
            events.append({
                'climate_zone': record[6],
                'species': record[5],
                'date': record[2],
                'daily_growth': record[3] - measurements[index - 1][3],
                'rolling_health': health,
            })

    by_zone = {}
    for event in events:
        by_zone.setdefault(event['climate_zone'], []).append(event)
    result = []
    for zone_events in by_zone.values():
        zone_events.sort(key=lambda e: (-e['daily_growth'], e['date']))
        result.extend(zone_events[:2])
    return result


def add_unseen_fixture():
    token = ''.join(secrets.choice(string.ascii_letters) for _ in range(12))
    zone = 'VerifierZone_' + token
    species_a = 'VerifierPlantA_' + token
    species_b = 'VerifierPlantB_' + token
    growth = 60 + secrets.randbelow(40)

    con = sqlite3.connect(DB_PATH)
    try:
        region_id = con.execute('SELECT COALESCE(MAX(region_id), 0) + 1 FROM regions').fetchone()[0]
        plant_id = con.execute('SELECT COALESCE(MAX(plant_id), 0) + 1 FROM plants').fetchone()[0]
        con.execute('INSERT INTO regions(region_id, name, climate_zone) VALUES (?, ?, ?)',
                    (region_id, 'Verifier Region ' + token, zone))
        con.execute('INSERT INTO plants(plant_id, species, region_id) VALUES (?, ?, ?)',
                    (plant_id, species_a, region_id))
        con.execute('INSERT INTO plants(plant_id, species, region_id) VALUES (?, ?, ?)',
                    (plant_id + 1, species_b, region_id))
        con.executemany('INSERT INTO measurements(plant_id, date, height_cm, health_score) VALUES (?, ?, ?, ?)', [
            (plant_id, '2037-01-01', 10, 3),
            (plant_id, '2037-01-02', 10 + growth, 7),
            (plant_id, '2037-01-03', 11 + growth, 11),
            (plant_id + 1, '2037-02-01', 20, 8),
            (plant_id + 1, '2037-02-02', 20 + growth - 1, 6),
        ])
        con.commit()
    finally:
        con.close()


def test_complete_solution():
    query = extract_report_query()

    # Preserve the original fixed-data assertions, but do not impose unspecified global ordering.
    run_script()
    assert_report(read_csv_rows(), BASELINE_EXPECTED, 'baseline CSV')
    assert_report(run_query_directly(query), BASELINE_EXPECTED, 'baseline SQL query')

    # Add values unknown to the submission, execute it again, and derive the oracle independently.
    add_unseen_fixture()
    expected = derive_expected_from_database()
    run_script()
    assert_report(read_csv_rows(), expected, 'dynamic CSV')
    assert_report(run_query_directly(query), expected, 'dynamic SQL query')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
