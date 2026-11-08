#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import sqlite3
import stat
import subprocess
import uuid

import pytest

SCRIPT_FILE = '/home/user/analyze_impact.py'
OUTPUT_FILE = '/home/user/blast_radius_p2.json'
DB_FILE = '/home/user/data/servers.db'
SERVICES_FILE = '/home/user/data/services.json'
SCHEMA_FILE = '/home/user/schema.json'


def run_script(expect_success=True):
    if os.path.lexists(OUTPUT_FILE):
        os.unlink(OUTPUT_FILE)
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', 'python3', SCRIPT_FILE],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    if expect_success:
        assert result.returncode == 0, (
            f'{SCRIPT_FILE} failed with exit code {result.returncode}.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        assert os.path.isfile(OUTPUT_FILE), f'Expected output file {OUTPUT_FILE} does not exist.'
    return result


def assert_uses_jsonschema(source, tree):
    module_aliases = set()
    imported_names = set()
    has_import = False

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'jsonschema' or alias.name.startswith('jsonschema.'):
                    has_import = True
                    module_aliases.add(alias.asname or alias.name.split('.')[0])
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module == 'jsonschema' or node.module.startswith('jsonschema.')):
                has_import = True
                for alias in node.names:
                    imported_names.add(alias.asname or alias.name)

    assert has_import, 'The script must import and use the jsonschema package.'

    def root_name(expr):
        while isinstance(expr, ast.Attribute):
            expr = expr.value
        return expr.id if isinstance(expr, ast.Name) else None

    used = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in imported_names:
            used = True
        elif isinstance(node.func, ast.Attribute):
            if root_name(node.func) in module_aliases:
                used = True
            elif node.func.attr in {'validate', 'is_valid', 'iter_errors', 'check_schema'}:
                used = True

    assert used, 'The script imports jsonschema but does not appear to call its validation API.'


def test_script_exists_is_python_and_executes():
    assert os.path.exists(SCRIPT_FILE), f'Expected script {SCRIPT_FILE} does not exist.'
    assert not os.path.islink(SCRIPT_FILE), f'{SCRIPT_FILE} must be a regular Python source file, not a symlink.'
    mode = os.stat(SCRIPT_FILE).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT_FILE} must be a regular file.'
    assert os.path.getsize(SCRIPT_FILE) > 0, f'{SCRIPT_FILE} is empty.'

    with open(SCRIPT_FILE, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_FILE)
    except SyntaxError as exc:
        pytest.fail(f'{SCRIPT_FILE} is not valid Python: {exc}')
    assert_uses_jsonschema(source, tree)

    run_script(expect_success=True)


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f'Expected output file {OUTPUT_FILE} does not exist.'


def test_output_file_content():
    assert os.path.isfile(OUTPUT_FILE), f'Output file {OUTPUT_FILE} is missing.'

    with open(OUTPUT_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {OUTPUT_FILE} is not valid JSON.')

    assert isinstance(data, list), 'Output should be a JSON array.'
    assert len(data) == 3, f'Expected exactly 3 items in the output array (page size 3), found {len(data)}.'

    expected_data = [
        {
            'service_id': 'SVC-B',
            'service_name': 'Billing',
            'priority': 90,
            'impact_distance': 1,
            'server_location': 'us-east-1'
        },
        {
            'service_id': 'SVC-E',
            'service_name': 'Email',
            'priority': 90,
            'impact_distance': 1,
            'server_location': 'eu-central-1'
        },
        {
            'service_id': 'SVC-H',
            'service_name': 'Helpdesk',
            'priority': 50,
            'impact_distance': 1,
            'server_location': 'us-east-1'
        }
    ]

    for i, expected_item in enumerate(expected_data):
        actual_item = data[i]
        assert actual_item == expected_item, f'Mismatch at index {i}. Expected {expected_item}, got {actual_item}.'


def compute_expected(services, locations):
    by_id = {service['service_id']: service for service in services}
    distances = {}
    queue = []

    for service in services:
        if service['runs_on_server'] == 'SRV-042':
            distances[service['service_id']] = 0
            queue.append(service['service_id'])

    position = 0
    while position < len(queue):
        impacted_id = queue[position]
        position += 1
        next_distance = distances[impacted_id] + 1
        for service in services:
            service_id = service['service_id']
            if impacted_id in service['depends_on']:
                if service_id not in distances or next_distance < distances[service_id]:
                    distances[service_id] = next_distance
                    queue.append(service_id)

    result = []
    for service_id, distance in distances.items():
        service = by_id[service_id]
        result.append({
            'service_id': service_id,
            'service_name': service['service_name'],
            'priority': service['priority'],
            'impact_distance': distance,
            'server_location': locations[service['runs_on_server']],
        })

    result.sort(key=lambda item: (-item['priority'], item['impact_distance'], item['service_id']))
    return result[3:6]


def test_recomputes_from_inputs_and_enforces_schema():
    with open(DB_FILE, 'rb') as f:
        original_db = f.read()
    with open(SERVICES_FILE, 'rb') as f:
        original_services = f.read()
    with open(SCHEMA_FILE, 'rb') as f:
        original_schema = f.read()

    token = uuid.uuid4().hex[:10]
    ids = [f'DYN-{token}-{letter}' for letter in 'ABCDEFGH']
    priorities = [80, 80, 100, 60, 90, 70, 50, 95]
    random.SystemRandom().shuffle(priorities)
    locations = {
        'SRV-001': f'east-{token}',
        'SRV-042': f'failed-{token}',
        'SRV-099': f'west-{token}',
    }
    services = [
        {'service_id': ids[0], 'service_name': f'RootOne-{token}', 'priority': priorities[0], 'runs_on_server': 'SRV-042', 'depends_on': []},
        {'service_id': ids[1], 'service_name': f'RootTwo-{token}', 'priority': priorities[1], 'runs_on_server': 'SRV-042', 'depends_on': []},
        {'service_id': ids[2], 'service_name': f'Child-{token}', 'priority': priorities[2], 'runs_on_server': 'SRV-001', 'depends_on': [ids[0]]},
        {'service_id': ids[3], 'service_name': f'Grandchild-{token}', 'priority': priorities[3], 'runs_on_server': 'SRV-099', 'depends_on': [ids[2]]},
        {'service_id': ids[4], 'service_name': f'ShortestPath-{token}', 'priority': priorities[4], 'runs_on_server': 'SRV-001', 'depends_on': [ids[3], ids[1]]},
        {'service_id': ids[5], 'service_name': f'Downstream-{token}', 'priority': priorities[5], 'runs_on_server': 'SRV-099', 'depends_on': [ids[4]]},
        {'service_id': ids[6], 'service_name': f'FarDownstream-{token}', 'priority': priorities[6], 'runs_on_server': 'SRV-001', 'depends_on': [ids[5]]},
        {'service_id': ids[7], 'service_name': f'Unaffected-{token}', 'priority': priorities[7], 'runs_on_server': 'SRV-099', 'depends_on': []},
    ]

    try:
        if os.path.exists(DB_FILE):
            os.unlink(DB_FILE)
        conn = sqlite3.connect(DB_FILE)
        conn.execute('CREATE TABLE servers (server_id TEXT PRIMARY KEY, hostname TEXT, location TEXT)')
        conn.executemany(
            'INSERT INTO servers VALUES (?, ?, ?)',
            [(server_id, f'host-{server_id}-{token}', location) for server_id, location in locations.items()],
        )
        conn.commit()
        conn.close()

        with open(SERVICES_FILE, 'w', encoding='utf-8') as f:
            json.dump(services, f)

        with open(original_schema.decode('utf-8'), 'r') if False else open(SCHEMA_FILE, 'w', encoding='utf-8') as f:
            f.write(original_schema.decode('utf-8'))

        expected = compute_expected(services, locations)
        run_script(expect_success=True)
        with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
            actual = json.load(f)
        assert actual == expected, f'Script did not recompute the dynamic blast radius. Expected {expected}, got {actual}.'

        schema = json.loads(original_schema.decode('utf-8'))
        schema['maxItems'] = 0
        with open(SCHEMA_FILE, 'w', encoding='utf-8') as f:
            json.dump(schema, f)

        run_script(expect_success=False)
        assert not os.path.exists(OUTPUT_FILE), (
            'The script produced an output that violates the supplied JSON schema; '
            'schema validation must occur before writing the report.'
        )
    finally:
        with open(DB_FILE, 'wb') as f:
            f.write(original_db)
        with open(SERVICES_FILE, 'wb') as f:
            f.write(original_services)
        with open(SCHEMA_FILE, 'wb') as f:
            f.write(original_schema)
        subprocess.run(
            ['runuser', '-u', 'user', '--', 'python3', SCRIPT_FILE],
            cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
