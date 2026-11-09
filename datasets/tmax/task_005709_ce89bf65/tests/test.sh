#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import pathlib
import re
import secrets
import shutil
import subprocess

HOME = pathlib.Path('/home/user')
CSV_PATH = HOME / 'employees.csv'
JSON_PATH = HOME / 'hierarchy.json'
CPP_PATH = HOME / 'aggregate_salary.cpp'
TOTAL_PATH = HOME / 'total_salary.txt'


def run(cmd, timeout=30):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout, check=True)


def load_expected():
    with CSV_PATH.open(newline='') as f:
        rows = list(csv.DictReader(f))
    assert rows, 'employees.csv is empty'
    expected = {}
    for row in rows:
        emp_id = row['emp_id']
        assert emp_id not in expected, f'duplicate employee {emp_id} in CSV'
        expected[emp_id] = {
            'emp_id': emp_id,
            'manager_id': row['manager_id'],
            'name': row['name'],
            'salary': int(row['salary']),
        }
    return expected


def salary_int(value):
    assert not isinstance(value, bool), 'salary cannot be boolean'
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str) and re.fullmatch(r'[+-]?\d+', value.strip()):
        return int(value.strip())
    raise AssertionError(f'invalid salary value: {value!r}')


def employee_objects(value):
    found = []
    def visit(node):
        if isinstance(node, dict):
            if 'emp_id' in node:
                found.append(node)
            for child in node.values():
                visit(child)
        elif isinstance(node, list):
            for child in node:
                visit(child)
    visit(value)
    return found


def parse_last_json(output):
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    for line in reversed(lines):
        try:
            return json.loads(line)
        except json.JSONDecodeError:
            pass
    raise AssertionError(f'mongosh did not emit JSON: {output!r}')


def verify_mongodb(expected):
    ps = run(['docker', 'ps', '-q']).stdout.split()
    matching = []
    for cid in ps:
        image = run(['docker', 'inspect', '-f', '{{.Config.Image}}', cid]).stdout.strip()
        if image == 'mongo:latest':
            ports = run(['docker', 'port', cid, '27017/tcp']).stdout
            if re.search(r':27017\s*$', ports, re.MULTILINE):
                matching.append(cid)
    assert matching, 'No running mongo:latest container exposes port 27017'

    uri = 'mongodb://127.0.0.1:27017/company'
    docs_out = run([
        'mongosh', uri, '--quiet', '--eval',
        'JSON.stringify(db.employees.find({}, {_id:0}).sort({emp_id:1}).toArray())'
    ]).stdout
    docs = parse_last_json(docs_out)
    assert isinstance(docs, list), 'employees collection query did not return an array'
    actual = {}
    for doc in docs:
        assert isinstance(doc, dict) and 'emp_id' in doc, f'invalid MongoDB document: {doc!r}'
        emp_id = str(doc['emp_id'])
        assert emp_id not in actual, f'duplicate MongoDB employee {emp_id}'
        actual[emp_id] = {
            'emp_id': emp_id,
            'manager_id': '' if doc.get('manager_id') is None else str(doc.get('manager_id', '')),
            'name': str(doc.get('name', '')),
            'salary': salary_int(doc.get('salary')),
        }
    assert actual == expected, f'MongoDB employees do not match employees.csv: {actual!r}'

    idx_out = run([
        'mongosh', uri, '--quiet', '--eval',
        'JSON.stringify(db.employees.getIndexes())'
    ]).stdout
    indexes = parse_last_json(idx_out)
    assert any(isinstance(i, dict) and isinstance(i.get('key'), dict)
               and i['key'].get('manager_id') in (1, -1) for i in indexes), \
        'employees collection has no index on manager_id'


def verify_graphlookup_script():
    candidates = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path in (CSV_PATH, JSON_PATH, CPP_PATH, TOTAL_PATH):
            continue
        if 'history' in path.name.lower() or path.stat().st_size > 1024 * 1024:
            continue
        try:
            text = path.read_text(errors='ignore')
        except OSError:
            continue
        if '$graphLookup' in text:
            candidates.append(str(path))
    assert candidates, 'No query script under /home/user uses $graphLookup'


def verify_hierarchy(data, expected):
    objects = employee_objects(data)
    by_id = {}
    for obj in objects:
        emp_id = str(obj['emp_id'])
        assert emp_id in expected, f'unexpected employee {emp_id} in hierarchy.json'
        assert emp_id not in by_id, f'employee {emp_id} appears more than once in hierarchy.json'
        assert 'salary' in obj, f'employee {emp_id} has no salary in hierarchy.json'
        by_id[emp_id] = obj
    assert set(by_id) == set(expected), \
        f'hierarchy.json employees differ from CEO hierarchy: found {sorted(by_id)}, expected {sorted(expected)}'
    for emp_id, obj in by_id.items():
        row = expected[emp_id]
        assert salary_int(obj['salary']) == row['salary'], f'wrong salary for {emp_id}'
        if 'manager_id' in obj:
            manager = '' if obj['manager_id'] is None else str(obj['manager_id'])
            assert manager == row['manager_id'], f'wrong manager for {emp_id}'
    return by_id


def main():
    # Preserve and strengthen all original artifact assertions.
    assert TOTAL_PATH.is_file(), f'Expected file {TOTAL_PATH} does not exist.'
    original_total = TOTAL_PATH.read_text().strip()
    assert '475000' in original_total, \
        f'Expected total salary 475000 in {TOTAL_PATH}, but found: {original_total}'
    assert CPP_PATH.is_file(), f'Expected C++ source file {CPP_PATH} does not exist.'
    assert JSON_PATH.is_file(), f'Expected JSON output file {JSON_PATH} does not exist.'

    expected = load_expected()
    expected_total = sum(row['salary'] for row in expected.values())
    assert re.fullmatch(r'[+-]?\d+', original_total), 'total_salary.txt must contain only an integer'
    assert int(original_total) == expected_total, \
        f'total_salary.txt contains {original_total}, expected {expected_total}'

    try:
        hierarchy = json.loads(JSON_PATH.read_text())
    except json.JSONDecodeError as e:
        raise AssertionError(f'hierarchy.json is not valid JSON: {e}')
    hierarchy_objects = verify_hierarchy(hierarchy, expected)

    verify_mongodb(expected)
    verify_graphlookup_script()

    # Compile and execute the submitted program against randomized salaries so a
    # prewritten constant cannot pass. Preserve each salary's JSON representation.
    randomized = {}
    for emp_id, obj in hierarchy_objects.items():
        value = secrets.randbelow(900000) + 1001
        randomized[emp_id] = value
        old = obj['salary']
        obj['salary'] = str(value) if isinstance(old, str) else value
    dynamic_expected = sum(randomized.values())

    hierarchy_backup = JSON_PATH.read_bytes()
    total_backup = TOTAL_PATH.read_bytes()
    csv_hidden = HOME / '.employees.csv.verifier-backup'
    binary = '/tmp/aggregate_salary_verifier'
    try:
        JSON_PATH.write_text(json.dumps(hierarchy))
        if csv_hidden.exists():
            csv_hidden.unlink()
        CSV_PATH.rename(csv_hidden)
        run(['g++', '-std=c++17', '-O2', str(CPP_PATH), '-o', binary], timeout=60)
        if TOTAL_PATH.exists():
            TOTAL_PATH.unlink()
        run([binary], timeout=30)
        assert TOTAL_PATH.is_file(), 'Compiled C++ program did not create total_salary.txt'
        dynamic_output = TOTAL_PATH.read_text().strip()
        assert re.fullmatch(r'[+-]?\d+', dynamic_output), \
            f'C++ output is not exactly an integer: {dynamic_output!r}'
        assert int(dynamic_output) == dynamic_expected, \
            f'C++ program produced {dynamic_output}; expected {dynamic_expected} for randomized hierarchy'
    finally:
        JSON_PATH.write_bytes(hierarchy_backup)
        TOTAL_PATH.write_bytes(total_backup)
        if csv_hidden.exists():
            csv_hidden.rename(CSV_PATH)
        try:
            os.unlink(binary)
        except FileNotFoundError:
            pass


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
