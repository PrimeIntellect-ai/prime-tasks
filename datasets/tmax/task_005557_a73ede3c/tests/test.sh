#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import json
import os
import random
import re
import secrets
import shlex
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

EXTRACT = '/home/user/extract.sh'
VALIDATE = '/home/user/validate.sh'
DB = '/home/user/company.db'
OUT = '/home/user/org_chart.json'


def run_extract():
    if os.path.exists(OUT):
        os.remove(OUT)
    result = subprocess.run([EXTRACT], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"extract.sh failed with return code {result.returncode}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(OUT), f"extract.sh did not create {OUT}."
    try:
        with open(OUT, encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{OUT} does not contain valid JSON: {exc}")


@contextlib.contextmanager
def audited_sqlite():
    sqlite_path = os.path.realpath(shutil.which('sqlite3'))
    backup_path = sqlite_path + '.verifier-' + uuid.uuid4().hex
    audit_path = '/tmp/sqlite-audit-' + uuid.uuid4().hex
    os.replace(sqlite_path, backup_path)
    wrapper = f'''#!/bin/bash
_tmp=$(mktemp)
cat > "$_tmp"
{{
  printf '%s\\n' "$@"
  cat "$_tmp"
}} >> {shlex.quote(audit_path)}
{shlex.quote(backup_path)} "$@" < "$_tmp"
_rc=$?
rm -f "$_tmp"
exit $_rc
'''
    try:
        with open(sqlite_path, 'w', encoding='utf-8') as f:
            f.write(wrapper)
        os.chmod(sqlite_path, 0o755)
        yield audit_path
    finally:
        try:
            os.remove(sqlite_path)
        except FileNotFoundError:
            pass
        os.replace(backup_path, sqlite_path)


def assert_records(actual, expected):
    assert isinstance(actual, list), f"JSON root must be an array, got {type(actual)}."
    assert len(actual) == len(expected), f"Expected {len(expected)} records, got {len(actual)}."
    for item in actual:
        assert isinstance(item, dict), f"Every output item must be an object, got {item!r}."
        assert set(item) == {'emp_id', 'name', 'manager_id', 'depth', 'path'}, (
            f"Incorrect output keys: {set(item)}"
        )
        assert type(item['emp_id']) is int
        assert isinstance(item['name'], str)
        assert item['manager_id'] is None or type(item['manager_id']) is int
        assert type(item['depth']) is int
        assert isinstance(item['path'], str)
    actual_sorted = sorted(actual, key=lambda x: x['emp_id'])
    expected_sorted = sorted(expected, key=lambda x: x['emp_id'])
    for got, want in zip(actual_sorted, expected_sorted):
        assert got == want, f"Record mismatch.\nExpected: {want}\nActual: {got}"


def install_generated_database(root_has_null_record):
    token = secrets.token_hex(8)
    ids = random.sample(range(10000, 90000), 8)
    names = [
        f"Chief {token}",
        f"O'Brien {token}",
        f"North Team {token}",
        f"Delta-{token}",
        f"Echo {token}",
        f"Foxtrot {token}",
        f"Gamma {token}",
        f"Last Person {token}",
    ]
    parents = [None, 0, 0, 1, 1, 2, 3, 5]

    if os.path.exists(DB):
        os.remove(DB)
    con = sqlite3.connect(DB)
    try:
        con.executescript('''
            CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE reporting (
                assignment_id INTEGER PRIMARY KEY,
                emp_id INTEGER,
                manager_id INTEGER,
                assigned_date TEXT
            );
        ''')
        con.executemany('INSERT INTO employees(id, name) VALUES (?, ?)', zip(ids, names))

        rows = []
        assignment = 1
        if root_has_null_record:
            rows.append((assignment, ids[0], ids[7], '1998-01-01'))
            assignment += 1
            rows.append((assignment, ids[0], None, '2025-01-01'))
            assignment += 1

        for child_index in range(1, len(ids)):
            parent_index = parents[child_index]
            # Current row.
            rows.append((assignment, ids[child_index], ids[parent_index], f'2025-02-{child_index + 10:02d}'))
            assignment += 1
            # A deliberately wrong stale row for every non-root employee.
            wrong_index = (parent_index + 1) % len(ids)
            if wrong_index == child_index:
                wrong_index = (wrong_index + 1) % len(ids)
            rows.append((assignment, ids[child_index], ids[wrong_index], f'2010-03-{child_index + 10:02d}'))
            assignment += 1

        random.shuffle(rows)
        con.executemany(
            'INSERT INTO reporting(assignment_id, emp_id, manager_id, assigned_date) VALUES (?, ?, ?, ?)',
            rows,
        )
        con.commit()
    finally:
        con.close()

    expected = []
    depths = [0] * len(ids)
    paths = [''] * len(ids)
    for i in range(len(ids)):
        if parents[i] is None:
            depths[i] = 0
            paths[i] = names[i]
            manager_id = None
        else:
            p = parents[i]
            depths[i] = depths[p] + 1
            paths[i] = paths[p] + ' -> ' + names[i]
            manager_id = ids[p]
        expected.append({
            'emp_id': ids[i],
            'name': names[i],
            'manager_id': manager_id,
            'depth': depths[i],
            'path': paths[i],
        })
    return expected


def write_temp_json(value=None, raw=None):
    f = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False, encoding='utf-8')
    try:
        if raw is not None:
            f.write(raw)
        else:
            json.dump(value, f)
        return f.name
    finally:
        f.close()


def test_extract_sh_exists_and_executable():
    assert os.path.isfile(EXTRACT), f"{EXTRACT} does not exist."
    assert os.access(EXTRACT, os.X_OK), f"{EXTRACT} is not executable."


def test_validate_sh_exists_and_executable():
    assert os.path.isfile(VALIDATE), f"{VALIDATE} does not exist."
    assert os.access(VALIDATE, os.X_OK), f"{VALIDATE} is not executable."


def test_extract_produces_correct_json_and_executes_recursive_sqlite_query():
    expected_original = [
        {'emp_id': 1, 'name': 'Alice', 'manager_id': None, 'depth': 0, 'path': 'Alice'},
        {'emp_id': 2, 'name': 'Bob', 'manager_id': 1, 'depth': 1, 'path': 'Alice -> Bob'},
        {'emp_id': 3, 'name': 'Charlie', 'manager_id': 2, 'depth': 2, 'path': 'Alice -> Bob -> Charlie'},
        {'emp_id': 4, 'name': 'David', 'manager_id': 3, 'depth': 3, 'path': 'Alice -> Bob -> Charlie -> David'},
        {'emp_id': 5, 'name': 'Eve', 'manager_id': 4, 'depth': 4, 'path': 'Alice -> Bob -> Charlie -> David -> Eve'},
    ]

    fd, db_backup = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    shutil.copy2(DB, db_backup)
    try:
        with audited_sqlite() as audit_path:
            assert_records(run_extract(), expected_original)

            # Unknown-at-build-time databases prevent a fixed five-object fixture
            # from passing and exercise both supported CEO representations.
            for root_has_null_record in (False, True):
                expected = install_generated_database(root_has_null_record)
                assert_records(run_extract(), expected)

            assert os.path.isfile(audit_path), 'extract.sh did not invoke the sqlite3 executable.'
            with open(audit_path, encoding='utf-8', errors='replace') as f:
                executed_sql = f.read()
            assert re.search(r'\bWITH\s+RECURSIVE\b', executed_sql, re.IGNORECASE), (
                'The SQL actually supplied to sqlite3 did not use a recursive CTE.'
            )
    finally:
        shutil.copy2(db_backup, DB)
        os.remove(db_backup)


def test_validate_sh_valid_json():
    # Retain the original valid-output assertion.
    data = run_extract()
    result = subprocess.run([VALIDATE, OUT], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"validate.sh failed on valid JSON with return code {result.returncode}\n"
        f"Stderr: {result.stderr}"
    )

    token = secrets.token_hex(10)
    count = 2 + secrets.randbelow(6)
    arbitrary_valid = []
    for i in range(count):
        arbitrary_valid.append({
            'path': f'{token} -> node {i}',
            'depth': i + 0.5,
            'manager_id': None if i == 0 else 7000 + i,
            'name': f'random name {token} {i}',
            'emp_id': 7000 + i,
        })

    for value in ([], arbitrary_valid):
        path = write_temp_json(value=value)
        try:
            result = subprocess.run([VALIDATE, path], capture_output=True, text=True)
            assert result.returncode == 0, (
                f"validate.sh rejected arbitrary valid JSON: {value!r}\n"
                f"stdout={result.stdout!r} stderr={result.stderr!r}"
            )
        finally:
            os.remove(path)


def test_validate_sh_invalid_json():
    # Retain the original invalid fixtures.
    bad_values = [
        ('raw', '[{"emp_id": 1, "name": "A"}]'),
        ('raw', '{"emp_id": 1, "name": "A", "manager_id": null, "depth": 0, "path": "A"}'),
        ('raw', '[{"emp_id": 1, "name": "A", "manager_id": null, "depth": "zero", "path": "A"}]'),
    ]

    token = secrets.token_hex(12)
    base = {
        'emp_id': secrets.randbelow(100000) + 1,
        'name': 'name-' + token,
        'manager_id': None,
        'depth': secrets.randbelow(20),
        'path': 'path-' + token,
    }
    missing_key = secrets.choice(list(base))
    missing = dict(base)
    del missing[missing_key]
    extra = dict(base)
    extra['unexpected_' + token] = True
    bad_depth = dict(base)
    bad_depth['depth'] = {'not': 'a number'}
    bad_path = dict(base)
    bad_path['path'] = ['not', 'a', 'string']

    bad_values.extend([
        ('value', base),                 # root is not an array
        ('value', [missing]),            # missing a required key
        ('value', [extra]),              # extra key
        ('value', [bad_depth]),          # wrong depth type
        ('value', [bad_path]),           # wrong path type
        ('value', [base, token]),        # non-object array member
        ('raw', '[{"emp_id":'),         # malformed JSON
    ])

    for i, (kind, content) in enumerate(bad_values):
        path = write_temp_json(raw=content) if kind == 'raw' else write_temp_json(value=content)
        try:
            result = subprocess.run([VALIDATE, path], capture_output=True, text=True)
            assert result.returncode == 1, (
                f"validate.sh should fail on bad JSON {i + 1} with return code 1, "
                f"but got {result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert result.stdout.strip(), (
                f"validate.sh must print an error message to stdout for bad JSON {i + 1}."
            )
        finally:
            os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
